require "date"
require_relative "./person"

class DataProcessor
  def self.create_people_from_csv_data(people_data, responses_data)
    people_data.map do |person_data|
      response_data = responses_data.find { |response| person_data["Email"] == response["Email address"] }
      week_commencing_fields = responses_data.headers
        .select { |header| header.match(/^Week commencing/) }
        .map do |week_commencing_field|
          {
            date: week_commencing_field.match(/^Week commencing (.+)$/)[1],
            availability: response_data[week_commencing_field].split(",").map(&:strip),
          }
        end

      person_args = {
        email: response_data["Email address"],
        team: response_data["What team/area are you in (or will be in when this rota starts)?"],
        non_working_days: non_working_days(response_data["Do you have any non working days? [Non working day(s)]"]),
        forbidden_in_hours_days: week_commencing_fields.map { |field|
          weekdays(field[:date]) if field[:availability].include?("Not available for in-hours")
        }.compact,
        forbidden_on_call_days: week_commencing_fields.map { |field|
          forbidden_dates = []
          forbidden_dates += weekdays(field[:date]) if field[:availability].include?("Not available for on-call weekday nights")
          forbidden_dates += weekends(field[:date]) if field[:availability].include?("Not available for on-call over the weekend")
          forbidden_dates.empty? ? nil : forbidden_dates
        }.compact.flatten,
        can_do_roles: [
          person_data["Eligible for in-hours primary?"] == "Yes" ? :inhours_primary : nil,
          person_data["Can do in-hours secondary?"] == "Yes" ? :inhours_secondary : nil,
          person_data["Eligible for in-hours primary?"] == "Yes" ? :inhours_primary_standby : nil,
          person_data["Can do in-hours secondary?"] == "Yes" ? :inhours_secondary_standby : nil,
          person_data["Should be scheduled for on-call?"] == "Yes" && person_data["Eligible for on-call primary?"] == "Yes" ? :oncall_primary : nil,
          person_data["Should be scheduled for on-call?"] == "Yes" && person_data["Eligible for on-call secondary?"] == "Yes" ? :oncall_secondary : nil,
        ].compact,
      }
      Person.new(**person_args)
    end
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
end
