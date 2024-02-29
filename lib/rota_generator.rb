require "yaml"

class RotaGenerator
  def initialize(dates:, people:, roles_config:)
    @dates = dates
    @people = people
    @roles_config = Roles.new(config: roles_config)
  end

  def fill_slots(algorithm: :daily)
    if algorithm == :daily
      fill_slots_daily
    elsif algorithm == :weekly
      fill_slots_weekly
    else
      raise "Invalid algorithm supplied"
    end
  end

  def fill_slots_daily
    people_queue = @people

    @dates.each do |date|
      day_of_week = Date.parse(date).strftime("%A")

      roles_to_fill = if %w[Saturday Sunday].include?(day_of_week)
                        @roles_config.by_type(%i[weekends])
                      else
                        @roles_config.by_type(%i[weekdays weeknights])
                      end

      roles_to_fill.each do |role|
        available_candidates = people_queue.select { |person| person.availability(date:).include?(role) }
        if available_candidates.empty?
          puts "NOBODY ABLE TO FILL #{role} on #{date}"
          break
        end

        person_to_assign = available_candidates.first
        person_to_assign.assign(role:, date:)
        people_queue.sort_by! { |person| @roles_config.value_of_shifts(person.assigned_shifts) }
      end
    end
  end

  def fill_slots_weekly
    weeks = @dates.each_slice(7).to_a
    stray_shifts = []
    weeks.each do |dates_for_week|
      puts "Assigning shifts for dates #{dates_for_week}..."
      teams_impacted = {
        weekdays: [],
        weeknights: [],
        weekends: [],
      }
      @roles_config.types.each do |role|
        dates_for_role = dates_for_week.select do |date|
          day_of_week = Date.parse(date).strftime("%A")
          if %w[Saturday Sunday].include?(day_of_week)
            @roles_config.by_type(%i[weekends]).include?(role)
          else
            @roles_config.by_type(%i[weekdays weeknights]).include?(role)
          end
        end

        puts "Assigning the #{role} role for dates #{dates_for_role}..."

        # Find people who can do this role
        candidates = @people.select { |candidate| candidate.can_do_role?(role) }
        # Sort people so that those with fewer shifts so far are the first to be considered
        candidates.sort_by! { |person| @roles_config.value_of_shifts(person.assigned_shifts) }
        # To avoid over-burdening teams, move folks who are in the same team as other folks covering shifts on this date
        push_to_back = candidates.select do |person|
          (@roles_config.config[role][:weekdays] && teams_impacted[:weekdays].include?(person.team)) ||
            (@roles_config.config[role][:weeknights] && teams_impacted[:weeknights].include?(person.team)) ||
            (@roles_config.config[role][:weekends] && teams_impacted[:weekends].include?(person.team))
        end
        candidates -= push_to_back
        candidates += push_to_back

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

        puts "Assigning #{person_to_assign.name}."
        dates_for_role.each do |date|
          person_to_assign.assign(role:, date:)

          (teams_impacted[:weekdays] << person_to_assign.team) if @roles_config.config[role][:weekdays]
          (teams_impacted[:weeknights] << person_to_assign.team) if @roles_config.config[role][:weeknights]
          (teams_impacted[:weekends] << person_to_assign.team) if @roles_config.config[role][:weekends]
        rescue ForbiddenDateException
          puts "Failed to assign #{person_to_assign.name} to #{role} on #{date}."
          stray_shifts << { role:, date: }
        end
      end
    end

    stray_shifts.each do |shift|
      date = shift[:date]
      role = shift[:role]
      # ensure people are ordered in terms of shift burden
      @people.sort_by! { |person| @roles_config.value_of_shifts(person.assigned_shifts) }
      person = @people.find { |candidate| candidate.availability(date:).include?(role) }
      if person.nil?
        puts "NOBODY ABLE TO FILL #{role} on #{date}"
      else
        # assign person to shift
        person.assign(role:, date:)
      end
    end
  end

  def write_rota(filepath:)
    roles = {}
    @roles_config.config.each do |key, value|
      roles[key.to_s] = value.transform_keys(&:to_s)
    end

    output = {
      dates: @dates,
      roles:,
      people: @people.map(&:to_h),
    }.transform_keys(&:to_s)

    File.write(filepath, output.to_yaml)
  end
end
