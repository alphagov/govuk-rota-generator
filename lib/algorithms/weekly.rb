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
          person_to_assign = find_most_suitable_candidate(candidates, role, dates_for_role)

          dates_for_role.each do |date|
            person_to_assign.assign(date:, role:)
          rescue ForbiddenDateException
            stray_shifts << { role:, date: }
          end
        end
      end
      assign_stray_shifts(stray_shifts)
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
      stray_shifts.each do |shift|
        date = shift[:date]
        role = shift[:role]

        @people = sort_people_by_value_of_shifts(@people)
        person = @people.find { |candidate| candidate.availability(date:).include?(role) }
        if person.nil?
          puts "NOBODY ABLE TO FILL #{role} on #{date}"
        else
          person.assign(role:, date:)
        end
      end
    end

    def self.inhours_role?(role_id)
      @roles_config.config[role_id][:weekdays]
    end

    def self.oncall_role?(role_id)
      !inhours_role?(role_id)
    end

    def self.balance_slots(people, roles)
      # only use people in our calculations if they have a chance of taking on a shift.
      # Anyone else just skews things.
      eligible_people = people.reject { |person| person.can_do_roles == [] }

      puts "Attempting to balance rota."
      least_to_most_burdened = eligible_people.sort_by { |person| roles.value_of_shifts(person.assigned_shifts) }
      burden_figures = least_to_most_burdened.map { |person| roles.value_of_shifts(person.assigned_shifts) }
      mean = burden_figures.sum(0.0) / burden_figures.size
      sum = burden_figures.sum(0.0) { |element| (element - mean)**2 }
      variance = sum / (burden_figures.size - 1)
      current_standard_deviation = Math.sqrt(variance)
      puts "    Mean = #{mean}, current standard_deviation = #{current_standard_deviation}"

      least_to_most_burdened.each do |person_a|
        # if index > (least_to_most_burdened.count / 2)
        #   # At roughly the halfway point, stop trying to reassign shifts.
        #   # It only ends up skewing the disparities even further, as the
        #   # most burdened engineers start reassigning their on-call shifts
        #   # and the in-hours shifts 'trickle down' to the lesser burdened
        #   # engineers on subsequent re-runs of `balance_slots`
        #   break
        # end

        most_to_least_burdened = least_to_most_burdened.reverse
        while (person_b = most_to_least_burdened.shift)
          next unless roles.value_of_shifts(person_a.assigned_shifts) < roles.value_of_shifts(person_b.assigned_shifts)

          change_made = false
          person_b.assigned_shifts.each do |shift|
            next unless person_a.availability(date: shift[:date]).include?(shift[:role])

            # puts "#{person_a.name} is taking over from #{person_b.name} for #{shift[:role]} on #{shift[:date]}"
            # puts "    Old burden distribution: #{roles.value_of_shifts(person_a.assigned_shifts)}, #{roles.value_of_shifts(person_b.assigned_shifts)}"
            person_a.assign(date: shift[:date], role: shift[:role])
            person_b.unassign(date: shift[:date], role: shift[:role])
            # puts "    New burden distribution: #{roles.value_of_shifts(person_a.assigned_shifts)}, #{roles.value_of_shifts(person_b.assigned_shifts)}"
            change_made = true
            break
          end

          unless change_made
            # puts "Unable to find any shift swap opportunities for #{person_a.name} (#{roles.value_of_shifts(person_a.assigned_shifts)}) and #{person_b.name} (#{roles.value_of_shifts(person_b.assigned_shifts)})"
          end
        end
      end

      puts "Did we improve things?"
      least_to_most_burdened = eligible_people.sort_by { |person| roles.value_of_shifts(person.assigned_shifts) }
      burden_figures = least_to_most_burdened.map { |person| roles.value_of_shifts(person.assigned_shifts) }
      mean = burden_figures.sum(0.0) / burden_figures.size
      sum = burden_figures.sum(0.0) { |element| (element - mean)**2 }
      variance = sum / (burden_figures.size - 1)
      standard_deviation = Math.sqrt(variance)
      puts "    New standard_deviation = #{standard_deviation} (before: #{current_standard_deviation})"

      standard_deviation
    end
  end
end
