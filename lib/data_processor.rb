require "csv"
require_relative "./person"

class InvalidStructureException < StandardError; end

class DataProcessor
  def self.combine(responses_csv:, people_csv:, filepath:)
    people_data = CSV.read(people_csv, headers: true)
    responses_data = CSV.read(responses_csv, headers: true)
    people = combine_raw(people_data, responses_data)
    File.write(filepath, people.map(&:to_h).to_yaml)
  end

  def self.validate_responses(responses_csv:)
    responses_data = CSV.read(responses_csv, headers: true)
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
      expected_next_date = (Date.parse(date_this_week) + 7).strftime("%d/%m/%Y")
      unless date_next_week == expected_next_date
        raise InvalidStructureException, "Expected 'Week commencing #{date_next_week}' to be 'Week commencing #{expected_next_date}'"
      end

      date_this_week = date_next_week
    end
  end

  def self.combine_raw(people_data, responses_data)
    people = []
    people_data.each do |person_data|
      response_data = responses_data.find { |response| person_data["Email"] == response["Email address"] }
      week_commencing_fields = responses_data.headers.select { |header| header.match(/^Week commencing/) }

      email = person_data["Email"]
      team = response_data.nil? ? "Unknown" : response_data["What team/area are you in (or will be in when this rota starts)?"]
      non_working_days = response_data.nil? ? [] : non_working_days(response_data)
      forbidden_in_hours_days = response_data.nil? ? [] : forbidden_in_hours_days(week_commencing_fields, response_data)
      forbidden_on_call_days = response_data.nil? ? [] : forbidden_on_call_days(week_commencing_fields, response_data)
      can_do_roles = [
        person_data["Eligible for in-hours primary?"] == "Yes" ? :inhours_primary : nil,
        person_data["Can do in-hours secondary?"] == "Yes" ? :inhours_secondary : nil,
        person_data["Eligible for in-hours primary?"] == "Yes" ? :inhours_primary_standby : nil,
        person_data["Can do in-hours secondary?"] == "Yes" ? :inhours_secondary_standby : nil,
        person_data["Should be scheduled for on-call?"] == "Yes" ? :oncall_primary : nil,
        person_data["Should be scheduled for on-call?"] == "Yes" ? :oncall_secondary : nil, # TODO: - currently no way of distinguishing people who are new to on call
      ].compact

      people << Person.new(
        email:,
        team:,
        non_working_days:,
        forbidden_in_hours_days:,
        forbidden_on_call_days:,
        can_do_roles:,
      )
    end
    people
  end

  def self.non_working_days(response_data)
    non_working_days = response_data["Do you have any non working days? [Non working day(s)]"].split(",")
    non_working_days = [] if non_working_days == [""]
    non_working_days.map { |abbreviated_day|
      return nil if abbreviated_day == ""

      Date.parse(abbreviated_day).strftime("%A")
    }.compact
  end

  def self.forbidden_in_hours_days(week_commencing_fields, response)
    forbidden_dates = []
    week_commencing_fields.each do |week_commencing_field|
      next unless (person_response = response[week_commencing_field])

      if availability_strings(person_response).include?("Not available for in-hours")
        forbidden_dates += weekdays(week_commencing_field)
      end
    end
    forbidden_dates
  end

  def self.forbidden_on_call_days(week_commencing_fields, response)
    forbidden_dates = []
    week_commencing_fields.each do |week_commencing_field|
      next unless (person_response = response[week_commencing_field])

      if availability_strings(person_response).include?("Not available for on-call weekday nights")
        forbidden_dates += weekdays(week_commencing_field)
      end

      if availability_strings(person_response).include?("Not available for on-call over the weekend")
        forbidden_dates += weekends(week_commencing_field)
      end
    end
    forbidden_dates
  end

  def self.availability_strings(person_response)
    person_response.split(",").map(&:strip)
  end

  def self.weekdays(week_commencing_field)
    (0..4).to_a.map do |n|
      first_unavailable_date = week_commencing_field.match(/^Week commencing (.+)$/)[1]
      (Date.parse(first_unavailable_date) + n).strftime("%d/%m/%Y")
    end
  end

  def self.weekends(week_commencing_field)
    monday = week_commencing_field.match(/^Week commencing (.+)$/)[1]
    saturday = (Date.parse(monday) + 5).strftime("%d/%m/%Y")
    sunday = (Date.parse(monday) + 6).strftime("%d/%m/%Y")
    [saturday, sunday]
  end
end