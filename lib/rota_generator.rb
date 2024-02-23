require "yaml"
require_relative "./person"
require_relative "./fairness_calculator"

class RotaGenerator
  attr_reader :people

  def initialize(yml: nil)
    unless yml.nil?
      people_array = YAML.load_file(yml, symbolize_names: true)
      @people = people_array.map { |person_data| Person.new(**person_data) }
    end
  end

  def slots_to_fill(dates, roles_to_fill)
    slots_to_fill = []
    dates.each do |date|
      roles_to_fill.each_key do |role|
        slots_to_fill << { date:, role: }
      end
    end
    slots_to_fill
  end

  def fill_slots(people, slots_to_fill, roles_config = {})
    @people = people
    dates = slots_to_fill.map { |slot| slot[:date] }.uniq.sort # TODO: dates
    fairness_calculator = FairnessCalculator.new(roles_config)

    dates.each do |date|
      roles_to_fill = slots_to_fill.select { |slot| slot[:date] == date }.map { |slot| slot[:role] }

      # EXAMPLE output:
      # { inhours_primary: [PersonA, PersonB], oncall_primary: [PersonA] }
      date_roles_availability = Hash[
        roles_to_fill.map { |role| [role, people.select { |person| person.availability(date:).include?(role) }] }
      ]

      # Sort the role allocation by sparsity of dev availability,
      # i.e. if a particular role can only be filled by one dev, assign that dev to that role first
      date_roles_availability = date_roles_availability.sort { |_role, available_devs| available_devs.count }

      devs_used = []
      date_roles_availability.each do |role, available_devs|
        # We could raise an exception, but it's usually more helpful to generate a rough rota.
        if available_devs.count.zero?
          puts "WARNING: nobody is available for #{role} on #{date}"
        elsif (remaining_devs = available_devs - devs_used) && remaining_devs.count.zero?
          puts "WARNING: can't fill #{role} on #{date} because all eligible devs are already assigned to other roles."
        else
          # prefer assigning shift to devs who have been given fewer shifts so far, or less burdensome shifts
          assignable_devs = remaining_devs.sort_by { |person| [fairness_calculator.weight_of_shifts(person.assigned_shifts), person.random_factor] }
          chosen_dev = assignable_devs.first
          chosen_dev.assign(role:, date:)
          devs_used << chosen_dev
        end
      end
    end

    slots_filled(people)
  end

  def slots_filled(people)
    shifts = people.reduce([]) do |arr, person|
      arr + person.assigned_shifts.map { |shift| shift.merge(assignee: person.name) }
    end
    shifts.sort_by { |shift| shift[:date] }
  end

  def to_h
    slots_filled(@people)
  end

  def to_csv
    slots = slots_filled(@people)
    dates = slots.map { |slot| slot[:date] }.uniq.sort { |a, b| Date.parse(a) <=> Date.parse(b) }
    roles = %i[inhours_primary inhours_secondary inhours_primary_standby inhours_secondary_standby oncall_primary oncall_secondary]
    columns = %w[date] + roles
    csv_lines = [columns]
    dates.each do |date|
      row = columns.map do |column|
        if column == "date"
          date
        else
          assigned_slot = slots.find { |slot| slot[:date] == date && slot[:role] == column }
          assigned_slot.nil? ? "" : assigned_slot[:assignee]
        end
      end
      csv_lines << row
    end
    csv_lines.map { |row| row.join(",") }.join("\n")
  end
end
