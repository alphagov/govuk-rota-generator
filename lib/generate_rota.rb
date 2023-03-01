require "csv"
require_relative "./person"

class CannotFillSlotException < StandardError; end

class GenerateRota
  def fill_slots(people, slots_to_fill)
    weeks = slots_to_fill.map { |slot| slot[:week] }.uniq.sort
    weeks.each do |week|
      roles_to_fill = slots_to_fill.select { |slot| slot[:week] == week }.map { |slot| slot[:role] }

      # EXAMPLE output:
      # { inhours_primary: [PersonA, PersonB], oncall_primary: [PersonA] }
      week_roles_availability = Hash[
        roles_to_fill.map {|role| [role, people.select { |person| person.availability(week: week).include?(role) }]}
      ]

      # Sort the role allocation by sparsity of dev availability,
      # i.e. if a particular role can only be filled by one dev, assign that dev to that role first
      week_roles_availability = week_roles_availability.sort { |role, available_devs| available_devs.count }

      devs_used = []
      week_roles_availability.each do |role, available_devs|
        if available_devs.count.zero?
          raise CannotFillSlotException.new("Nobody is available for the #{role} in week #{week}")
        elsif ((remaining_devs = available_devs - devs_used) && remaining_devs.count.zero?)
          raise CannotFillSlotException.new("Can't fill #{role} in week #{week} because all eligible devs are already assigned to other roles.")
        end

        # prefer assigning shift to devs who have been given fewer shifts so far
        chosen_dev = remaining_devs.sort_by { |person| person.assigned_shifts.count }.first
        chosen_dev.assign(role: role, week: week)
        devs_used << chosen_dev
      end
    end

    slots_filled(people)
  end

  def slots_filled(people)
    shifts = people.reduce([]) do |arr, person|
      arr + person.assigned_shifts.map { |shift| shift.merge(assignee: person.name) }
    end
    shifts.sort_by { |shift| shift[:week] }
  end
end
