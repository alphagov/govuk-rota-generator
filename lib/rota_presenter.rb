require "csv"
require "yaml"
require_relative "./person"
require_relative "./roles"

class BadRotaPresenterArgs < StandardError; end

class RotaPresenter
  def initialize(args)
    if args[:filepath]
      rota = YAML.load_file(args[:filepath], symbolize_names: true)
      @dates = rota[:dates]
      @people = rota[:people].map { |person_data| Person.new(**person_data) }
    elsif %i[dates people].all? { |param| args.include?(param) }
      @dates = args[:dates]
      @people = args[:people]
    else
      raise BadRotaPresenterArgs, "Invalid parameters provided to RotaPresenter"
    end
  end

  def to_yaml
    {
      dates: @dates,
      people: @people.map(&:to_h),
    }.transform_keys(&:to_s).to_yaml
  end

  def to_csv_daily
    columns = %w[date] + roles
    rows = [columns]
    rows += @dates.map do |date|
      columns.map do |column|
        if column == "date"
          date
        else
          person = @people.find { |candidate| candidate.assigned_shifts.include?({ date:, role: column }) }
          person.nil? ? "" : person.name
        end
      end
    end
    multidimensional_array_to_csv(rows)
  end

  def to_csv_weekly
    weeks = @dates.each_slice(7).to_a
    columns = %w[week] + roles
    rows = [columns]
    rows += weeks.map do |dates_for_week|
      columns.map do |column|
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
          name_of_person_with_most_shifts = grouped.max { |a, b| a[1].count <=> b[1].count }[0]
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
    end
    multidimensional_array_to_csv(rows)
  end

  def fairness_summary(roles_config:)
    roles_config = Roles.new(config: roles_config)
    sorted_people = @people.sort_by { |person| - roles_config.value_of_shifts(person.assigned_shifts) }
    people_summaries = sorted_people.map do |person|
      shifts = person
        .assigned_shifts
        .group_by { |shift| shift[:role] }
        .map { |role, grouped_shifts| "#{grouped_shifts.count} #{role}" }
        .join(", ")

      if person.assigned_shifts.count.zero?
        "#{person.name} was not assigned to any shifts.'n" \
        "  (They're eligible for #{person.can_do_roles == [] ? 'no roles' : person.can_do_roles})."
      else
        "#{person.name} has #{roles_config.value_of_shifts(person.assigned_shifts)} " \
        "units of inconvenience, made up of #{person.assigned_shifts.count} shifts " \
        "including #{shifts}." \
      end
    end
    people_summaries.join("\n")
  end

private

  def roles
    @people.map(&:assigned_shifts).flatten.map { |shift| shift[:role] }.uniq.sort
  end

  def multidimensional_array_to_csv(rows)
    CSV.generate do |csv|
      rows.each do |row|
        csv << row
      end
    end
  end
end
