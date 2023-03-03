require "csv"
require_relative "./person"

class CannotFillSlotException < StandardError; end

class GenerateRota
  def initialize(csv: nil)
    unless csv.nil?
      @people = parse_csv_data(CSV.read(csv, headers: true))
    end
  end

  def generate(weeks_to_generate:, roles_to_fill:)
    puts "We want to generate a rota of #{weeks_to_generate} weeks, with the following roles in each week: #{roles_to_fill.keys.join(", ")}"
    slots_to_fill = []
    weeks_to_generate.times.each do |index|
      roles_to_fill.keys.each do |role|
        slots_to_fill << { week: (index + 1), role: role }
      end
    end

    puts "There are #{slots_to_fill.count} slots to fill, and #{@people.count} people on the rota."
    puts "Each person therefore needs to take an average of #{slots_to_fill.count.to_f / @people.count.to_f} slot(s)."
    fill_slots(@people, slots_to_fill)
    puts "All shifts allocated."

    puts "Checking fairness of spread:"
    @people.sort_by { |person| person.assigned_shifts.count }.reverse.each do |person|
      shift_types = person.assigned_shifts.map { |shift| shift[:role] }.uniq
      shift_totals = shift_types.map do |role|
        shift_count = person.assigned_shifts.select { |shift| shift[:role] == role }.count
        "#{shift_count} #{role}"
      end
      puts "#{person.name} has been allocated #{person.assigned_shifts.count} shifts (#{shift_totals.join(',')})"
    end
  end

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
          break unless role_mandatory?(role) # silently ignore issue unless role is mandatory
          raise CannotFillSlotException.new("Nobody is available for the #{role} in week #{week}")
        elsif ((remaining_devs = available_devs - devs_used) && remaining_devs.count.zero?)
          break unless role_mandatory?(role) # silently ignore issue unless role is mandatory
          raise CannotFillSlotException.new("Can't fill #{role} in week #{week} because all eligible devs are already assigned to other roles.")
        end

        # prefer assigning shift to devs who have been given fewer shifts so far, or less burdensome shifts
        chosen_dev = remaining_devs.sort_by { |person| person.weight_of_shifts }.first
        chosen_dev.assign(role: role, week: week)
        devs_used << chosen_dev
      end
    end

    slots_filled(people)
  end

  # TODO: find better way of marking as optional
  def role_mandatory?(role)
    role != :inhours_shadow
  end

  def slots_filled(people)
    shifts = people.reduce([]) do |arr, person|
      arr + person.assigned_shifts.map { |shift| shift.merge(assignee: person.name) }
    end
    shifts.sort_by { |shift| shift[:week] }
  end

  def to_h
    slots_filled(@people)
  end

  def to_csv
    slots = slots_filled(@people)
    weeks = slots.map { |slot| slot[:week] }.uniq.sort.last
    roles = slots.map { |slot| slot[:role] }.uniq
    columns = ["week"] + roles
    csv_lines = [columns]
    weeks.times.each do |week_index|
      roles_that_week = slots.select { |slot| slot[:week] == week_index + 1 }
      row = columns.map do |column|
        week = week_index + 1
        if column == "week"
          week
        else
          assigned_slot = slots.find { |slot| slot[:week] == (week_index + 1) && slot[:role] == column }
          assigned_slot.nil? ? "" : assigned_slot[:assignee]
        end
      end
      csv_lines << row
    end
    csv_lines.each do |row|
      puts row.join(",")
    end
  end

  private

  def parse_csv_data(csv_data)
    csv_data.each.with_index(1).map do |row|
      person_hash = row.to_h.transform_keys(&:to_sym)
      forbidden_weeks = person_hash[:forbidden_weeks].nil? ? [] : person_hash[:forbidden_weeks].split(",").map(&:to_i)
      can_do_roles = [
        person_hash[:can_do_inhours_primary] == "true" ? :inhours_primary : nil,
        person_hash[:can_do_inhours_secondary] == "true" ? :inhours_secondary : nil,
        person_hash[:can_do_inhours_shadow] == "true" ? :inhours_shadow : nil,
        person_hash[:can_do_inhours_primary_standby] == "true" ? :inhours_primary_standby : nil,
        person_hash[:can_do_inhours_secondary_standby] == "true" ? :inhours_secondary_standby : nil,
        person_hash[:can_do_oncall_primary] == "true" ? :oncall_primary : nil,
        person_hash[:can_do_oncall_secondary] == "true" ? :oncall_secondary : nil,
      ].compact
      Person.new(
        name: person_hash[:name],
        team: person_hash[:team],
        forbidden_weeks: forbidden_weeks,
        can_do_roles: can_do_roles,
      )
    end
  end
end
