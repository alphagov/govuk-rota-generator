require "csv"
require_relative "./person"

class CannotFillSlotException < StandardError; end

class GenerateRota
  def fill_slots(people, slots_to_fill)
    weeks = slots_to_fill.map { |slot| slot[:week] }.uniq
    people_availability = []
    people_availability_with_names = []
    weeks.each do |week|
      people.each do |person|
        person.availability(week: week).each do |available_role|
          people_availability << { week: week, role: available_role }
          people_availability_with_names << { week: week, role: available_role, person: person }
        end
      end
    end

    slots_to_fill.each do |slot|
      raise CannotFillSlotException.new("Nobody is available for the #{slot[:role]} in week #{slot[:week]}") unless people_availability.include?(slot)

      eligible_people = people_availability_with_names.select { |hsh| hsh[:week] == slot[:week] && hsh[:role] == slot[:role] }.map { |hsh| hsh[:person] }
      eligible_people = eligible_people.sort_by { |person| person.assigned_shifts.count }
      eligible_people.first.assign(role: slot[:role], week: slot[:week])
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
