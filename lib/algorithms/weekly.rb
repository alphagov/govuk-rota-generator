require "httparty"
require_relative "../data_processor"
require_relative "../roles"

module Algorithms
  class Weekly
    def self.fill_slots!(people:, dates:, roles_config:)
      @people = people
      @roles_config = Roles.new(config: roles_config)
      stray_shifts = []

      inhours_roles = @roles_config.by_type(%i[weekdays]).sort
      oncall_roles = @roles_config.by_type(%i[weeknights weekends]).sort
      (oncall_roles + inhours_roles).each do |role|
        week_batches(dates).each do |dates_for_week|
          dates_for_role = get_dates_for_role(dates_for_week, role)

          candidates = @people.select { |candidate| candidate.can_do_role?(role) }
          candidates = sort_people_by_value_of_shifts(candidates)
          candidates = push_teammates_to_back_of_queue(candidates, role, dates_for_week)

          last_resort_candidates = candidates_who_had_a_shift_last_or_next_week(candidates, dates_for_week)
          candidates_who_have_had_a_break = candidates - last_resort_candidates
          person_to_assign = find_most_suitable_candidate(candidates_who_have_had_a_break, role, dates_for_role)

          dates_for_role.each do |date|
            person_to_assign.assign(date:, role:)
          rescue ForbiddenDateException
            stray_shifts << { role:, date: }
          end
        end
      end
      assign_stray_shifts(stray_shifts)
      override_bank_holiday_daytime_shifts(people, dates)
    end

    def self.week_batches(dates)
      dates.each_slice(7).to_a
    end

    def self.get_dates_for_role(dates_for_week, role)
      dates_for_week.select do |date|
        day_of_week = Date.parse(date).strftime("%A")
        if %w[Saturday Sunday].include?(day_of_week)
          @roles_config.by_type(%i[weekends]).include?(role)
        else
          @roles_config.by_type(%i[weekdays weeknights]).include?(role)
        end
      end
    end

    def self.sort_people_by_value_of_shifts(people)
      # ensure people are ordered in terms of shift burden
      people.sort_by { |person| @roles_config.value_of_shifts(person.assigned_shifts) }
    end

    def self.candidates_who_had_a_shift_last_or_next_week(candidates, dates_for_week)
      last_week_dates = dates_for_week.map { |date| DataProcessor.format_date(Date.parse(date) - 7) }
      next_week_dates = dates_for_week.map { |date| DataProcessor.format_date(Date.parse(date) + 7) }
      dates = last_week_dates + next_week_dates
      candidates.select do |candidate|
        candidate
          .assigned_shifts
          .select { |shift| dates.include?(shift[:date]) }
          .any?
      end
    end

    def self.push_teammates_to_back_of_queue(people, role, dates_for_week)
      # To avoid over-burdening teams, move folks who are in the same team as other folks covering shifts on this date
      # But only for same shift type, e.g. in-hours Primary and in-hours Secondary
      people_already_assigned_similar_role_this_week = people.select do |person|
        roles_assigned_this_week = person
          .assigned_shifts
          .select { |shift| dates_for_week.include?(shift[:date]) }
          .map { |shift| shift[:role] }
          .uniq

        roles_assigned_this_week.any? do |assigned_role|
          (inhours_role?(assigned_role) && inhours_role?(role)) ||
            (oncall_role?(assigned_role) && oncall_role?(role))
        end
      end
      teams = people_already_assigned_similar_role_this_week.map(&:team).uniq

      people_to_push_to_back = []
      people.each do |person|
        if teams.include?(person.team)
          people.delete(person)
          people_to_push_to_back << person
        end
      end
      people + people_to_push_to_back
    end

    def self.find_most_suitable_candidate(candidates, role, dates_for_role)
      first_candidate_that_can_do_majority_of_dates = candidates.find do |candidate|
        dates_they_can_do = dates_for_role.map { |date|
          candidate.availability(date:).include?(role)
        } - [false]
        dates_they_can_do.count.to_f / dates_for_role.count > 0.5
      end

      person_to_assign = first_candidate_that_can_do_majority_of_dates
      if first_candidate_that_can_do_majority_of_dates.nil?
        puts "Nobody able to fill #{role} for the majority of the shift #{dates_for_role}. Doing piecemeal assignment instead..."
        person_to_assign = candidates.first
      end
      person_to_assign
    end

    def self.assign_stray_shifts(stray_shifts)
      sorted_candidates = sort_people_by_value_of_shifts(@people)
      last_resort_candidates = candidates_who_had_a_shift_last_or_next_week(sorted_candidates, stray_shifts.map { |shift| shift[:date] })

      stray_shifts.each do |shift|
        date = shift[:date]
        role = shift[:role]

        candidates_who_have_had_a_break = sorted_candidates - last_resort_candidates
        person = candidates_who_have_had_a_break.find { |candidate| candidate.availability(date:).include?(role) } ||
          last_resort_candidates.find { |candidate| candidate.availability(date:).include?(role) }
        if person.nil?
          puts "NOBODY ABLE TO FILL #{role} on #{date}"
        else
          person.assign(role:, date:)
        end
      end
    end

    def self.override_bank_holiday_daytime_shifts(people, dates)
      bank_holiday_dates(dates).each do |date|
        # TODO: it would be great to make this generic and not duplicate the role names here from the roles config,
        # but we're stuck with the hack below because we're having to overwrite _two_ roles, and we want to do
        # that somewhat consistently (i.e. oncall primary -> inhours primary, oncall secondary -> inhours secondary)
        inhours_primary = people.find { |person| person.assigned_shifts.include?({ date:, role: :inhours_primary }) }
        inhours_secondary = people.find { |person| person.assigned_shifts.include?({ date:, role: :inhours_secondary }) }
        on_call_primary = people.find { |person| person.assigned_shifts.include?({ date:, role: :oncall_primary }) }
        on_call_secondary = people.find { |person| person.assigned_shifts.include?({ date:, role: :oncall_secondary }) }

        inhours_primary.unassign(role: :inhours_primary, date:)
        inhours_secondary.unassign(role: :inhours_secondary, date:)
        on_call_primary.assign(role: :inhours_primary, date:, force: true)
        on_call_secondary.assign(role: :inhours_secondary, date:, force: true)
      end
    end

    def self.bank_holiday_dates(dates)
      bank_holidays = HTTParty.get("https://www.gov.uk/bank-holidays.json")
      bank_holiday_dates = bank_holidays["england-and-wales"]["events"].map do |event|
        DataProcessor.format_date(Date.parse(event["date"]))
      end
      dates & bank_holiday_dates
    end

    def self.inhours_role?(role_id)
      @roles_config.config[role_id][:weekdays]
    end

    def self.oncall_role?(role_id)
      !inhours_role?(role_id)
    end
  end
end
