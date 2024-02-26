require "csv"
require_relative "./person"
require_relative "./fairness_calculator"

class RotaGenerator
  attr_reader :people

  def initialize(csv: nil)
    unless csv.nil?
      @people = parse_csv_data(CSV.read(csv, headers: true))
    end
  end

  def slots_to_fill(weeks_to_generate, roles_to_fill)
    slots_to_fill = []
    weeks_to_generate.times.each do |index|
      roles_to_fill.each_key do |role|
        slots_to_fill << { week: (index + 1), role: }
      end
    end
    slots_to_fill
  end

  def fill_slots(people, slots_to_fill, roles_config = {})
    weeks = slots_to_fill.map { |slot| slot[:week] }.uniq.sort
    fairness_calculator = FairnessCalculator.new(roles_config)

    weeks.each do |week|
      roles_to_fill = slots_to_fill.select { |slot| slot[:week] == week }.map { |slot| slot[:role] }

      # EXAMPLE output:
      # { inhours_primary: [PersonA, PersonB], oncall_primary: [PersonA] }
      week_roles_availability = Hash[
        roles_to_fill.map { |role| [role, people.select { |person| person.availability(week:).include?(role) }] }
      ]

      # Sort the role allocation by sparsity of dev availability,
      # i.e. if a particular role can only be filled by one dev, assign that dev to that role first
      week_roles_availability = week_roles_availability.sort { |_role, available_devs| available_devs.count }

      devs_used = []
      week_roles_availability.each do |role, available_devs|
        # We could raise an exception, but it's usually more helpful to generate a rough rota.
        if available_devs.count.zero?
          puts "WARNING: nobody is available for #{role} in week #{week}"
        elsif (remaining_devs = available_devs - devs_used) && remaining_devs.count.zero?
          puts "WARNING: can't fill #{role} in week #{week} because all eligible devs are already assigned to other roles."
        else
          # prefer assigning shift to devs who have been given fewer shifts so far, or less burdensome shifts
          assignable_devs = remaining_devs.sort_by { |person| [fairness_calculator.weight_of_shifts(person.assigned_shifts), person.random_factor] }
          chosen_dev = assignable_devs.first
          chosen_dev.assign(role:, week:)
          devs_used << chosen_dev
        end
      end
    end

    slots_filled(people)
  end

  def slots_filled(people)
    shifts = people.reduce([]) do |arr, person|
      arr + person.assigned_shifts.map { |shift| shift.merge(assignee: person.email) }
    end
    shifts.sort_by { |shift| shift[:week] }
  end

  def to_h
    slots_filled(@people)
  end

  def to_csv
    slots = slots_filled(@people)
    weeks = slots.map { |slot| slot[:week] }.uniq.max
    roles = %i[inhours_primary inhours_secondary inhours_primary_standby inhours_secondary_standby oncall_primary oncall_secondary]
    columns = %w[week] + roles
    csv_lines = [columns]
    weeks.times.each do |week_index|
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
    csv_lines.map { |row| row.join(",") }.join("\n")
  end

private

  def parse_csv_data(csv_data)
    csv_data.each.with_index(1).map do |row|
      person_hash = row.to_h.transform_keys(&:to_sym)
      forbidden_weeks = person_hash[:forbidden_weeks].nil? ? [] : person_hash[:forbidden_weeks].split(",").map(&:to_i)
      can_do_roles = [
        person_hash[:can_do_inhours_primary] == "true" ? :inhours_primary : nil,
        person_hash[:can_do_inhours_secondary] == "true" ? :inhours_secondary : nil,
        person_hash[:can_do_inhours_primary_standby] == "true" ? :inhours_primary_standby : nil,
        person_hash[:can_do_inhours_secondary_standby] == "true" ? :inhours_secondary_standby : nil,
        person_hash[:can_do_oncall_primary] == "true" ? :oncall_primary : nil,
        person_hash[:can_do_oncall_secondary] == "true" ? :oncall_secondary : nil,
      ].compact
      Person.new(
        email: person_hash[:email],
        team: person_hash[:team],
        forbidden_weeks:,
        can_do_roles:,
      )
    end
  end
end
