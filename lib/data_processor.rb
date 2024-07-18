require "csv"
require "date"
require_relative "./person"
require_relative "./rota_presenter"

class InvalidStructureException < StandardError; end

class DataProcessor
  def self.combine_csvs(responses_csv:, people_csv:, filepath:)
    people_data = CSV.read(people_csv, headers: true)
    responses_data = CSV.read(responses_csv, headers: true)
    people = create_people_from_csv_data(people_data, responses_data)

    week_commencing_dates = responses_data.headers
      .select { |header| header.match(/^Week commencing/) }
      .map { |header| header.match(/^Week commencing (.+)$/)[1] }
    last_date = format_date(Date.parse(week_commencing_dates.last) + 6)

    File.write(filepath, RotaPresenter.new(people:, dates: date_range(week_commencing_dates.first, last_date)).to_yaml)
  end

  def self.create_people_from_csv_data(people_data, responses_data)
    validate_responses(responses_data)

    people = people_data.map do |person_data|
      next unless person_data["Email"]

      email = person_data["Email"]
      response_data = responses_data.find { |response| email == response["Email address"] }
      week_commencing_fields = []
      unless response_data.nil?
        week_commencing_fields = responses_data.headers
          .select { |header| header.match(/^Week commencing/) && response_data[header] }
          .map do |week_commencing_field|
            {
              date: week_commencing_field.match(/^Week commencing (.+)$/)[1],
              availability: response_data[week_commencing_field].split(",").map(&:strip),
            }
          end
      end

      person_args = {
        email:,
        team: response_data ? response_data["What team/area are you in (or will be in when this rota starts)?"] : "Unknown",
        non_working_days: response_data ? non_working_days(response_data["Do you have any non working days? [Non working day(s)]"]) : [],
        forbidden_in_hours_days: week_commencing_fields.map { |field|
          weekdays(field[:date]) if field[:availability].include?("Not available for in-hours")
        }.compact.flatten,
        forbidden_on_call_days: week_commencing_fields.map { |field|
          forbidden_dates = []
          forbidden_dates += weekdays(field[:date]) if field[:availability].include?("Not available for on-call weekday nights")
          forbidden_dates += weekends(field[:date]) if field[:availability].include?("Not available for on-call over the weekend")
          forbidden_dates.empty? ? nil : forbidden_dates
        }.compact.flatten,
        can_do_roles: [
          person_data["Eligible for in-hours Primary?"] == "Yes" ? :inhours_primary : nil,
          person_data["Eligible for in-hours Secondary?"] == "Yes" ? :inhours_secondary : nil,
          person_data["Eligible for in-hours Secondary?"] == "Yes" ? :inhours_standby : nil,
          person_data["Eligible for on-call Primary?"] == "Yes" ? :oncall_primary : nil,
          person_data["Eligible for on-call Secondary?"] == "Yes" ? :oncall_secondary : nil,
        ].compact,
      }

      Person.new(**person_args)
    end

    people.compact
  end

  def self.non_working_days(comma_separated_days)
    non_working_days = comma_separated_days.split(",")
    non_working_days = [] if non_working_days == [""]
    non_working_days.map { |abbreviated_day|
      return nil if abbreviated_day == ""

      Date.parse(abbreviated_day).strftime("%A")
    }.compact
  end

  def self.weekdays(first_unavailable_date)
    (0..4).to_a.map do |n|
      format_date(Date.parse(first_unavailable_date) + n)
    end
  end

  def self.weekends(monday)
    saturday = format_date(Date.parse(monday) + 5)
    sunday = format_date(Date.parse(monday) + 6)
    [saturday, sunday]
  end

  def self.format_date(parsed_date)
    parsed_date.strftime("%d/%m/%Y")
  end

  def self.date_range(first_date, last_date)
    dates = [first_date]
    tmp = first_date
    while tmp != last_date
      tmp = format_date(Date.parse(tmp) + 1)
      dates << tmp
    end
    dates
  end

  def self.validate_responses(responses_data)
    columns = responses_data.headers
    first_columns_regexes = [
      /^Timestamp$/,
      /^Email address$/,
      /^Have you been given an exemption from on call\?/,
      /^Do you have any non working days\?/,
      /^What team\/area are you in/,
      /^If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours/,
    ]
    week_commencing_regex = /^Week commencing \d+{2}\/\d{2}\/\d{4}$/
    last_column_regex = /^Need to elaborate on any of the above\?/

    first_columns = columns.shift(first_columns_regexes.count).each_with_index.map do |column, index|
      { regex: first_columns_regexes[index], value: column }
    end
    last_column = [columns.pop].map { |column| { regex: last_column_regex, value: column } }
    week_columns = columns.map { |column| { regex: week_commencing_regex, value: column } }

    (first_columns + week_columns + last_column).each do |hash|
      unless hash[:value].match(hash[:regex])
        raise InvalidStructureException, "Expected '#{hash[:value]}' to match '#{hash[:regex]}'"
      end
    end

    validate_week_dates(week_columns.map { |hash| hash[:value].sub("Week commencing ", "") })

    true
  end

  def self.validate_week_dates(week_dates)
    date_this_week = week_dates.shift(1).first
    day_of_week = Date.parse(date_this_week).strftime("%A")

    unless day_of_week == "Monday"
      raise InvalidStructureException, "Expected column 'Week commencing #{date_this_week}' to correspond to a Monday, but it's a #{day_of_week}."
    end

    week_dates.each do |date_next_week|
      expected_next_date = format_date(Date.parse(date_this_week) + 7)
      unless date_next_week == expected_next_date
        raise InvalidStructureException, "Expected 'Week commencing #{date_next_week}' to be 'Week commencing #{expected_next_date}'"
      end

      date_this_week = date_next_week
    end
  end

  def self.parse_csv(rota_csv:, roles_config:, rota_yml_output:)
    rota_csv = CSV.read(rota_csv, headers: true)

    people_data = {}
    rota_csv.each do |week_data|
      (week_data.headers - %w[week]).each do |role|
        name = week_data[role]
        next if name.nil?

        overrides = []
        if name.include?("(")
          # e.g. "Dev Eloper (Carl E on 09/04/2024, Jo C on 10/04/2024)"
          overrides = name.match(/\((.+)\)/)[1].split(",").map do |override|
            parts = override.strip.match(/(.+) on (.+)/)
            { name: parts[1], date: parts[2] }
          end
          name = name.match(/^(.+) \(/)[1]
        end

        people_data[name] = { assigned_shifts: [] } unless people_data[name]
        date_range(*week_data["week"].split("-")).each do |date|
          next if overrides.find { |override| override[:date] == date }

          next if !roles_config[role.to_sym][:weekends] && %w[Saturday Sunday].include?(Date.parse(date).strftime("%A"))

          people_data[name][:assigned_shifts] << { role: role.to_sym, date: }
        end

        overrides.each do |override|
          people_data[override[:name]] = { assigned_shifts: [] } unless people_data[override[:name]]
          people_data[override[:name]][:assigned_shifts] << { role: role.to_sym, date: override[:date] }
        end
      end
    end
    people = people_data.map do |name, person_data|
      Person.new(
        email: "#{name.downcase.sub(' ', '.')}@digital.cabinet-office.gov.uk",
        team: "Unknown",
        assigned_shifts: person_data[:assigned_shifts],
        can_do_roles: person_data[:assigned_shifts].map { |shift| shift[:role].to_sym }.uniq,
      ).to_h
    end

    first_date = rota_csv.first["week"].split("-").first
    last_date = rota_csv.to_a.last.first.split("-").last
    dates = date_range(first_date, last_date)

    File.write(rota_yml_output, RotaPresenter.new(dates:, people:).to_yaml)
  end
end
