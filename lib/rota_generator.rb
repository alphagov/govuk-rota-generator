class RotaGenerator
  def initialize(dates:, people:, roles_config:)
    @dates = dates
    @people = people
    @roles_config = roles_config
  end

  def fill_slots
    people_queue = @people
    puts "People: #{@people.inspect}"

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
        while(!candidate.can_do_role?(role) && counter < people_queue.count)
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


    # dates = slots_to_fill.map { |slot| slot[:date] }.uniq.sort

    # dates.each do |date|
    #   roles_to_fill = slots_to_fill.select { |slot| slot[:date] == date }.map { |slot| slot[:role] }

    #   # EXAMPLE output:
    #   # { inhours_primary: [PersonA, PersonB], oncall_primary: [PersonA] }
    #   date_roles_availability = Hash[
    #     roles_to_fill.map { |role| [role, people.select { |person| person.availability(date:).include?(role) }] }
    #   ]

    #   # Sort the role allocation by sparsity of dev availability,
    #   # i.e. if a particular role can only be filled by one dev, assign that dev to that role first
    #   date_roles_availability = date_roles_availability.sort { |_role, available_devs| available_devs.count }

    #   devs_used = []
    #   date_roles_availability.each do |role, available_devs|
    #     # We could raise an exception, but it's usually more helpful to generate a rough rota.
    #     if available_devs.count.zero?
    #       puts "WARNING: nobody is available for #{role} on #{date}"
    #     elsif (remaining_devs = available_devs - devs_used) && remaining_devs.count.zero?
    #       puts "WARNING: can't fill #{role} on #{date} because all eligible devs are already assigned to other roles."
    #     else
    #       # prefer assigning shift to devs who have been given fewer shifts so far, or less burdensome shifts
    #       assignable_devs = remaining_devs.sort_by { |person| [fairness_calculator.weight_of_shifts(person.assigned_shifts), person.random_factor] }
    #       chosen_dev = assignable_devs.first
    #       chosen_dev.assign(role:, date:)
    #       devs_used << chosen_dev
    #     end
    #   end
    # end
  end
end
