class RotaGenerator
  def initialize(dates:, people:, roles_config:)
    @dates = dates
    @people = people
    @roles_config = roles_config
  end

  def fill_slots(group_weekly: false)
    people_queue = @people
    puts "People: #{@people.inspect}"

    if group_weekly
      # TODO - batch-assign entire week
      # THEN check availability afterwards and swap out folks later
      weeks = @dates.each_slice(7).to_a

      stray_shifts= []
      weeks.each do |dates_for_week|
        roles_to_fill = @roles_config.keys
        puts "filling #{roles_to_fill} for dates #{dates_for_week}"
        roles_to_fill.each do |role|
          # find first person in queue who can do this role
          person = people_queue.find { |person| person.can_do_role?(role) }

          if person.nil?
            puts "NOBODY ABLE TO FILL #{role} on #{dates_for_week}"
          else
            # find dates for this role to be assigned
            puts "finding dates for this role..."
            dates_for_role = dates_for_week.select do |date|
              day_of_week = Date.parse(date).strftime("%A")
              !(%i[
                inhours_primary
                inhours_primary_standby
                inhours_secondary
                inhours_secondary_standby
              ].include?(role) && %w[Saturday Sunday].include?(day_of_week))
            end

            # assign person to shifts
            dates_for_role.each do |date|
              begin
                person.assign(role:, date:)
              rescue ForbiddenDateException
                stray_shifts << { role:, date: }
              end
            end
            # put person at back of queue
            people_queue.delete(person)
            people_queue << person
          end
        end
      end

      stray_shifts.each do |shift|
        date = shift[:date]
        role = shift[:role]
        person = people_queue.find { |person| person.availability(date:).include?(role) }
        if person.nil?
          puts "NOBODY ABLE TO FILL #{role} on #{date}"
        else
          # assign person to shift
          person.assign(role:, date:)
          # put person at back of queue
          people_queue.delete(person)
          people_queue << person
        end
      end

    else
      @dates.each do |date|
        puts "Filling date #{date}"

        day_of_week = Date.parse(date).strftime("%A")
        roles_to_fill = @roles_config.keys
        if %w[Saturday Sunday].include?(day_of_week)
          roles_to_fill -= %i[
            inhours_primary
            inhours_primary_standby
            inhours_secondary
            inhours_secondary_standby
          ]
        else
          roles_to_fill -= %i[
            oncall_primary
            oncall_secondary
          ]
        end

        if roles_to_fill.empty?
          puts "no roles to fill"
        end

        roles_to_fill.each do |role|
          puts "Filling role #{role}"
          counter = 1
          candidate = people_queue.first
          puts "initial candidate #{candidate.email}"
          while(!candidate.can_do_role?(role) && counter < people_queue.count) # TODO use availability
            puts "can't do role - rotating candidate"
            people_queue.rotate!(1)
            candidate = people_queue.first
            counter += 1
          end
          puts "final candidate #{candidate.email}"
          if counter == people_queue.count
            puts "NOBODY ABLE TO FILL #{role} on #{date}"
          else
            candidate.assign(role:, date:)
            people_queue.rotate!(1)
          end
        end
      end
    end
  end

  def to_csv(group_weekly: false)
    roles = @roles_config.keys
    csv_lines = []

    if group_weekly
      weeks = @dates.each_slice(7).to_a
      columns = %w[week] + roles
      csv_lines = [columns]
      weeks.each do |dates_for_week|
        row = columns.map do |column|
          if column == "week"
            "#{dates_for_week.first}-#{dates_for_week.last}"
          else
            people_covering_role_this_week = dates_for_week.map do |date|
              person = @people.find { |person| person.assigned_shifts.include?({ date:, role: column }) }
              person.nil? ? nil : { name: person.name, date: }
            end

            people_covering_role_this_week.compact!
            if people_covering_role_this_week.nil?
              raise "No people covering #{column} for dates #{dates_for_week}"
            end

            grouped = people_covering_role_this_week.group_by { |shift| shift[:name] }
            name_of_person_with_most_shifts = grouped.keys.first
            if grouped.count  == 1
              name_of_person_with_most_shifts
            else
              # need to find the person with the most shifts, and then specify the remainder as overrides
              remainders = people_covering_role_this_week.reject { |shift| shift[:name] == name_of_person_with_most_shifts }
              remainder_strings = remainders.map { |remainder| "#{remainder[:name]} on #{remainder[:date]}" }
              "#{name_of_person_with_most_shifts} (#{remainder_strings.join(', ')})"
            end
          end
        end
        csv_lines << row
      end
    else
      columns = %w[date] + roles
      csv_lines = [columns]
      @dates.each do |date|
        row = columns.map do |column|
          if column == "date"
            date
          else
            person = @people.find { |person| person.assigned_shifts.include?({ date:, role: column }) }
            person.nil? ? "" : person.name
          end
        end
        csv_lines << row
      end
    end

    csv_lines.map { |row| row.join(",") }.join("\n")
  end
end
