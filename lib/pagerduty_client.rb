require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/time/zones"
require "httparty"
Time.zone = "Europe/London"

class PagerdutyClient
  #  PagerDuty's maximum: https://developer.pagerduty.com/docs/ZG9jOjExMDI5NTU4-pagination#classic-pagination
  API_LIMIT = 100

  def initialize(api_token:)
    raise "Missing PagerDuty API token" unless api_token

    @api_token = api_token
  end

  def users
    offset = 0
    users = []
    loop do
      batch_results = HTTParty.get(
        "https://api.pagerduty.com/users?limit=#{API_LIMIT}&offset=#{offset}",
        headers: {
          "Content-Type" => "application/json",
          "Accept" => "application/vnd.pagerduty+json;version=2",
          "Authorization" => "Token token=#{@api_token}",
        },
      )
      users << batch_results["users"]
      break unless batch_results["more"]

      offset += API_LIMIT
    end
    users.flatten
  end

  def assigned_shifts_this_schedule(schedule_id, from_date, to_date)
    schedule(schedule_id, Time.zone.parse(from_date).iso8601, (Time.zone.parse(to_date) + 1.day + 9.5.hours).iso8601)
  end

  def schedule(schedule_id, since_datetime, until_datetime)
    HTTParty.get(
      "https://api.pagerduty.com/schedules/#{schedule_id}?since=#{since_datetime}&until=#{until_datetime}",
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/vnd.pagerduty+json;version=2",
        "Authorization" => "Token token=#{@api_token}",
      },
    )["schedule"]["final_schedule"]["rendered_schedule_entries"]
  end

  def shifts_assigned_to_wrong_person(shifts_to_assign, assigned_shifts_this_schedule)
    shifts_to_assign.flatten.reject do |shift_to_assign|
      currently_assigned = assigned_shifts_this_schedule.find do |existing_shift|
        existing_shift["start"] == shift_to_assign[:start_datetime] &&
          existing_shift["end"] == shift_to_assign[:end_datetime]
      end
      currently_assigned && currently_assigned["user"]["summary"] == shift_to_assign[:person].name # person already assigned to this slot
    end
  end

  def in_past?(datetime)
    Time.zone.parse(datetime) <= Time.zone.now
  end

  def shifts_within_timespan(start_datetime, end_datetime, existing_pagerduty_shifts)
    existing_pagerduty_shifts.select do |shift|
      Time.zone.parse(shift["start"]) >= Time.zone.parse(start_datetime) &&
        Time.zone.parse(shift["end"]) <= Time.zone.parse(end_datetime)
    end
  end

  def create_override(schedule_id, pagerduty_user_id, start_datetime, end_datetime)
    override = {
      override: {
        start: start_datetime,
        end: end_datetime,
        user: {
          id: pagerduty_user_id,
          type: "user_reference",
        },
      },
    }

    HTTParty.post(
      "https://api.pagerduty.com/schedules/#{schedule_id}/overrides",
      body: override.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/vnd.pagerduty+json;version=2",
        "Authorization" => "Token token=#{@api_token}",
      },
    )
  end
end
