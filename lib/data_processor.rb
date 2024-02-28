require "csv"
require "date"
require "yaml"
require_relative "./person"

class InvalidStructureException < StandardError; end

class DataProcessor
  def self.combine(responses_csv:, people_csv:, filepath:)
    people_data = CSV.read(people_csv, headers: true)
    responses_data = CSV.read(responses_csv, headers: true)
    people = combine_raw(people_data, responses_data)
    output = {
      "dates" => dates(responses_data.headers.select { |header| header.match(/^Week commencing/) }),
      "people" => people.map(&:to_h),
    }

    File.write(filepath, output.to_yaml)
  end

  def self.combine_raw(people_data, responses_data)
    people = []
    people_data.each do |person_data|
      response_data = responses_data.find { |response| person_data["Email"] == response["Email address"] }
      week_commencing_fields = responses_data.headers.select { |header| header.match(/^Week commencing/) }

      email = response_data["Email address"]
      team = response_data["What team/area are you in (or will be in when this rota starts)?"]
      non_working_days = non_working_days(response_data)
      forbidden_in_hours_days = forbidden_in_hours_days(week_commencing_fields, response_data)
      forbidden_on_call_days = forbidden_on_call_days(week_commencing_fields, response_data)
      can_do_roles = [
        person_data["Eligible for in-hours primary?"] == "Yes" ? :inhours_primary : nil,
        person_data["Can do in-hours secondary?"] == "Yes" ? :inhours_secondary : nil,
        person_data["Eligible for in-hours primary?"] == "Yes" ? :inhours_primary_standby : nil,
        person_data["Can do in-hours secondary?"] == "Yes" ? :inhours_secondary_standby : nil,
        person_data["Should be scheduled for on-call?"] == "Yes" && person_data["Eligible for on-call primary?"] == "Yes" ? :oncall_primary : nil,
        person_data["Should be scheduled for on-call?"] == "Yes" && person_data["Eligible for on-call secondary?"] == "Yes" ? :oncall_secondary : nil,
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

  def self.dates(week_commencing_fields)
    first_date = week_commencing_fields.first.match(/^Week commencing (.+)$/)[1]
    last_date = (Date.parse(week_commencing_fields.last.match(/^Week commencing (.+)$/)[1]) + 6).strftime("%d/%m/%Y")
    dates = [first_date]
    tmp = first_date
    while tmp != last_date
      tmp = (Date.parse(tmp) + 1).strftime("%d/%m/%Y")
      dates << tmp
    end
    dates
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
