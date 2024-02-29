require_relative "./person"
require_relative "./roles"

class RotaPresenter
  def initialize(filepath:)
    rota = YAML.load_file(filepath, symbolize_names: true)
    @dates = rota[:dates]
    @people = rota[:people].map { |person_data| Person.new(**person_data) }
    @roles_config = Roles.new(config: rota[:roles])
  end

  def to_csv(summarised: :daily)
    if summarised == :daily
      to_csv_daily
    elsif summarised == :weekly
      to_csv_weekly
    else
      raise "Summarisation arg #{summarised} not recognised"
    end
  end

  def to_csv_daily
    roles = @roles_config.types
    csv_lines = []

    columns = %w[date] + roles
    csv_lines = [columns]
    @dates.each do |date|
      row = columns.map do |column|
        if column == "date"
          date
        else
          person = @people.find { |candidate| candidate.assigned_shifts.include?({ date:, role: column }) }
          person.nil? ? "" : person.name
        end
      end
      csv_lines << row
    end

    csv_lines.map { |row| row.join(",") }.join("\n")
  end

  def to_csv_weekly
    roles = @roles_config.types
    weeks = @dates.each_slice(7).to_a
    columns = %w[week] + roles
    csv_lines = [columns]
    weeks.each do |dates_for_week|
      row = columns.map do |column|
        if column == "week"
          "#{dates_for_week.first}-#{dates_for_week.last}"
        else
          people_covering_role_this_week = dates_for_week.map do |date|
            person = @people.find { |candidate| candidate.assigned_shifts.include?({ date:, role: column }) }
            person.nil? ? nil : { name: person.name, date: }
          end

          people_covering_role_this_week.compact!
          if people_covering_role_this_week.nil?
            raise "No people covering #{column} for dates #{dates_for_week}"
          end

          grouped = people_covering_role_this_week.group_by { |shift| shift[:name] }
          name_of_person_with_most_shifts = grouped.keys.first
          if grouped.count == 1
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

    csv_lines.map { |row| row.join(",") }.join("\n")
  end

  def self.fairness_summary(people:, roles_config:)
    sorted_people = people.sort_by { |person| - roles_config.value_of_shifts(person.assigned_shifts) }
    people_summaries = sorted_people.map do |person|
      shifts = person
        .assigned_shifts
        .group_by { |shift| shift[:role] }
        .map { |role, grouped_shifts| "#{grouped_shifts.count} #{role}" }
        .join(", ")

      if person.assigned_shifts.count.zero?
        "#{person.name} was not assigned to any shifts. " \
        "They're eligible for #{person.can_do_roles == [] ? 'no roles' : person.can_do_roles}."
      else
        "#{person.name} has #{roles_config.value_of_shifts(person.assigned_shifts)} " \
        "units of inconvenience, made up of #{person.assigned_shifts.count} shifts " \
        "including #{shifts}.\n" \
        "  (They're available for #{person.can_do_roles})"
      end
    end
    people_summaries.join("\n")
  end
end
