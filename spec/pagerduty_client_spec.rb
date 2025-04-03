require "pagerduty_client"
require_relative "../lib/person"

RSpec.describe PagerdutyClient do
  let(:user) do
    {
      "id" => "P69OQXR",
      "name" => "Some User",
      "email" => "some-user@digital.cabinet-office.gov.uk",
      "teams" => [
        {
          "id" => "PG4Z8YR",
          "type" => "team_reference",
          "summary" => "GOV.UK",
        },
      ],
    }
  end

  describe ".initialize" do
    it "takes an API token" do
      client = described_class.new(api_token: "foo")

      expect(client).to be_instance_of(described_class)
    end

    it "raises an error if token is nil" do
      expect { described_class.new(api_token: nil) }.to raise_exception("Missing PagerDuty API token")
    end
  end

  describe "#users" do
    it "paginates through the list of users" do
      request_1 = stub_request(:get, "https://api.pagerduty.com/users?limit=100&offset=0")
        .to_return(
          headers: { "Content-Type" => "application/json" },
          body: {
            users: [
              user,
              # imagine there are 99 more
            ],
            limit: 100,
            offset: 0,
            more: true,
          }.to_json,
        )
      request_2 = stub_request(:get, "https://api.pagerduty.com/users?limit=100&offset=100")
        .to_return(
          headers: { "Content-Type" => "application/json" },
          body: {
            users: [
              user, # pretend this is a different user to the one from the first request. It doesn't really matter.
              # as before, imagine there are up to 99 more
            ],
            limit: 100,
            offset: 100,
            more: false,
          }.to_json,
        )

      pd = described_class.new(api_token: "foo")
      expect(pd.users).to eq([user, user])
      expect(request_1).to have_been_requested
      expect(request_2).to have_been_requested
    end
  end

  describe "#assigned_shifts_this_schedule" do
    it "figures out the timestamp for 9:30am the day after the last day of the rota, and passes that to #schedule" do
      pd = described_class.new(api_token: "foo")
      schedule_id = "schedule_id"
      from_date = "01/01/1970"
      to_date = "02/01/1970"
      formatted_from_date = "1970-01-01T00:00:00+01:00"
      manipulated_to_date = "1970-01-03T09:30:00+01:00"
      return_value = "bar"

      allow(pd).to receive(:schedule).with(schedule_id, formatted_from_date, manipulated_to_date).and_return(return_value)
      expect(pd).to receive(:schedule).with(schedule_id, formatted_from_date, manipulated_to_date)
      expect(pd.assigned_shifts_this_schedule(schedule_id, from_date, to_date)).to eq(return_value)
    end
  end

  describe "#schedule" do
    it "retrieves a specific schedule between two dates" do
      schedule_id = "P999ABC"
      from_date = "2024-04-01T00:00:00+01:00"
      to_date = "2024-04-08T00:00:00+01:00"
      rendered_schedule_entries = [
        {
          # on-call person 'carried over' from previous week
          start: "2024-04-01T00:00:00+01:00",
          end: "2024-04-01T09:30:00+01:00",
          user: {
            id: "PRTM7I7",
            summary: "Andrew O'Neil",
          },
          id: "Q00SXW3CI01234",
        },
        {
          # beginning of new week in-hours (Monday)
          start: "2024-04-01T09:30:00+01:00",
          end: "2024-04-01T17:30:00+01:00",
          user: {
            id: "PRTM7I8",
            summary: "Someone else",
          },
          id: "Q00SXW3CI02345",
        },
        {
          # beginning of new week on-call (Monday overnight)
          start: "2024-04-01T17:30:00+01:00",
          end: "2024-04-02T09:30:00+01:00",
          user: {
            id: "PRTM7I9",
            summary: "Another person",
          },
          id: "Q00SXW3CI04567",
        },
        {
          # Tuesday
          start: "2024-04-02T09:30:00+01:00",
          end: "2024-04-02T17:30:00+01:00",
          user: {
            id: "PRTM7I8",
            summary: "Someone else",
          },
          id: "Q00SXW3CI02345",
        },
        {
          # Tuesday overnight
          start: "2024-04-02T17:30:00+01:00",
          end: "2024-04-03T09:30:00+01:00",
          user: {
            id: "PRTM7I9",
            summary: "Another person",
          },
          id: "Q00SXW3CI04567",
        },
        # ...and so on
        {
          # last day of week
          start: "2024-04-05T09:30:00+01:00",
          end: "2024-04-05T17:30:00+01:00",
          user: {
            id: "PRTM7I8",
            summary: "Someone else",
          },
          id: "Q00SXW3CI02345",
        },
        {
          # last on-call of week, including weekend shift
          # (actual on-call shift continues until 9:30 on 8th April,
          # but only goes to midnight here as that is the limit we've
          # specified with the `until` URL param)
          start: "2024-04-05T17:30:00+01:00",
          end: "2024-04-08T00:00:00+01:00",
          user: {
            id: "PRTM7I9",
            summary: "Another person",
          },
          id: "Q00SXW3CI04567",
        },
      ]
      api_response = {
        schedule: {
          final_schedule: {
            rendered_schedule_entries:,
          },
        },
      }

      stub_request(
        :get,
        "https://api.pagerduty.com/schedules/#{schedule_id}?since=2024-04-01T00:00:00%2001:00&until=2024-04-08T00:00:00%2001:00",
      ).to_return(
        headers: { "Content-Type" => "application/json" },
        body: api_response.to_json,
      )

      pd = described_class.new(api_token: "foo")
      expect(pd.schedule(schedule_id, from_date, to_date).to_json).to eq(rendered_schedule_entries.to_json)
    end
  end

  describe "#shifts_assigned_to_wrong_person" do
    it "returns the subset of shifts that need to be overridden" do
      assigned_shifts_this_schedule = [
        {
          "start" => "2024-04-09T17:30:00+01:00",
          "end" => "2024-04-10T09:30:00+01:00",
          "user" => {
            "id" => "PRTM7I8",
            "summary" => "John",
          },
        },
        {
          "start" => "2024-04-11T17:30:00+01:00",
          "end" => "2024-04-12T09:30:00+01:00",
          "user" => {
            "id" => "PRTM7I9",
            "summary" => "Janice",
          },
        },
      ]
      john = Person.new(email: "John@example.com", team: "Foo", can_do_roles: %i[oncall_primary])
      # This one is correctly assigned in `assigned_shifts_this_schedule`
      already_assigned = {
        person: john,
        role: :oncall_primary,
        start_datetime: "2024-04-09T17:30:00+01:00",
        end_datetime: "2024-04-10T09:30:00+01:00",
      }
      # This shift is missing from `assigned_shifts_this_schedule`
      missing = {
        person: john,
        role: :oncall_primary,
        start_datetime: "2024-04-10T17:30:00+01:00",
        end_datetime: "2024-04-11T09:30:00+01:00",
      }
      # This shift is assigned to the wrong person in `assigned_shifts_this_schedule`
      incorrectly_assigned = {
        person: john,
        role: :oncall_primary,
        start_datetime: "2024-04-11T17:30:00+01:00",
        end_datetime: "2024-04-12T09:30:00+01:00",
      }
      shifts_to_assign = [
        already_assigned,
        missing,
        incorrectly_assigned,
      ]

      pd = described_class.new(api_token: "foo")
      expect(pd.shifts_assigned_to_wrong_person(shifts_to_assign, assigned_shifts_this_schedule)).to eq([
        missing,
        incorrectly_assigned,
      ])
    end

    it "doesn't complain if the shift is represented slightly differently for the same person" do
      john = Person.new(email: "John@example.com", team: "Foo", can_do_roles: %i[oncall_primary])
      in_hours_shift = {
        person: john,
        role: :oncall_primary,
        start_datetime: "2025-05-05T09:30:00+01:00",
        end_datetime: "2025-05-05T17:30:00+01:00",
      }
      out_of_hours_shift = {
        person: john,
        role: :oncall_primary,
        start_datetime: "2025-05-05T17:30:00+01:00",
        end_datetime: "2025-05-06T09:30:00+01:00",
      }
      shifts_to_assign = [
        in_hours_shift,
        out_of_hours_shift,
      ]

      # John has already been assigned the full shift (in-hours rolling into out-of-hours)
      assigned_shifts_this_schedule = [
        {
          "start" => "2025-05-05T09:30:00+01:00",
          "end" => "2025-05-06T09:30:00+01:00",
          "user" => {
            "id" => "PRTM7I8",
            "summary" => "John",
          },
        },
      ]

      # `shifts_assigned_to_wrong_person` should return empty array, i.e. everything is OK
      pd = described_class.new(api_token: "foo")
      expect(pd.shifts_assigned_to_wrong_person(shifts_to_assign, assigned_shifts_this_schedule)).to eq([])
    end

    it "doesn't complain if the assigned shifts span a greater timespan than is being queried" do
      john = Person.new(email: "John@example.com", team: "Foo", can_do_roles: %i[oncall_primary])
      shifts_to_assign = [
        {
          person: john,
          role: :oncall_primary,
          start_datetime: "2025-05-05T10:00:00+01:00",
          end_datetime: "2025-05-05T11:00:00+01:00",
        },
      ]

      # John has already been assigned this shift and also time 'surrounding' it
      assigned_shifts_this_schedule = [
        {
          "start" => "2025-05-04T09:30:00+01:00",
          "end" => "2025-05-06T09:30:00+01:00",
          "user" => {
            "id" => "PRTM7I8",
            "summary" => "John",
          },
        },
      ]

      # `shifts_assigned_to_wrong_person` should return empty array, i.e. everything is OK
      pd = described_class.new(api_token: "foo")
      expect(pd.shifts_assigned_to_wrong_person(shifts_to_assign, assigned_shifts_this_schedule)).to eq([])
    end
  end

  describe "#in_past?" do
    let(:pd) { described_class.new(api_token: "foo") }

    it "returns true if the datetime is in the past" do
      expect(pd.in_past?("2019-01-01T09:30:00+01:00")).to be(true)
    end

    it "returns false if the datetime is in the future" do
      expect(pd.in_past?("3000-01-01T09:30:00+01:00")).to be(false)
    end
  end

  describe "#find_corresponding_shifts" do
    it "returns the PagerDuty shifts covered by the start/end datetime" do
      shift_to_assign = {
        start_datetime: "2024-04-01T17:30:00+01:00",
        end_datetime: "2024-04-02T17:30:00+01:00",
      }

      first_pd_shift = {
        "start" => "2024-04-01T17:30:00+01:00",
        "end" => "2024-04-02T09:30:00+01:00",
      }
      second_pd_shift = {
        "start" => "2024-04-02T09:30:00+01:00",
        "end" => "2024-04-02T17:30:00+01:00",
      }
      third_pd_shift = {
        "start" => "2024-04-02T17:30:00+01:00",
        "end" => "2024-04-03T09:30:00+01:00",
      }
      existing_pagerduty_shifts = [
        first_pd_shift,
        second_pd_shift,
        third_pd_shift,
      ]

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts(existing_pagerduty_shifts, shift_to_assign)).to eq([
        first_pd_shift,
        second_pd_shift,
      ])
    end

    it "catches exact shift matches" do
      pd_shift = {
        "start" => "2024-04-01T17:30:00+01:00",
        "end" => "2024-04-02T09:30:00+01:00",
      }

      shift_to_assign = {
        start_datetime: "2024-04-01T17:30:00+01:00",
        end_datetime: "2024-04-02T09:30:00+01:00",
      }

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts([pd_shift], shift_to_assign)).to eq([
        pd_shift,
      ])
    end

    it "catches shifts that start and end during the window" do
      shift_to_assign = {
        start_datetime: "2024-04-01T09:00:00+01:00",
        end_datetime: "2024-04-01T11:00:00+01:00",
      }
      pd_shift_that_encapsulates_the_window = {
        "start" => "2024-04-01T08:00:00+01:00",
        "end" => "2024-04-01T12:00:00+01:00",
      }

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts([pd_shift_that_encapsulates_the_window], shift_to_assign)).to eq([
        pd_shift_that_encapsulates_the_window,
      ])
    end

    it "catches shifts that start during the window but finish afterwards" do
      shift_to_assign = {
        start_datetime: "2024-04-01T09:00:00+01:00",
        end_datetime: "2024-04-01T11:00:00+01:00",
      }
      overlapping_pd_shift = {
        "start" => "2024-04-01T10:00:00+01:00",
        "end" => "2024-04-01T12:00:00+01:00",
      }

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts([overlapping_pd_shift], shift_to_assign)).to eq([
        overlapping_pd_shift,
      ])
    end

    it "catches shifts that end during the window but start before" do
      shift_to_assign = {
        start_datetime: "2024-04-01T09:00:00+01:00",
        end_datetime: "2024-04-01T11:00:00+01:00",
      }
      overlapping_pd_shift = {
        "start" => "2024-04-01T08:00:00+01:00",
        "end" => "2024-04-01T10:00:00+01:00",
      }

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts([overlapping_pd_shift], shift_to_assign)).to eq([
        overlapping_pd_shift,
      ])
    end

    it "rejects shifts that end at the start time" do
      shift_to_assign = {
        start_datetime: "2024-04-01T09:00:00+01:00",
        end_datetime: "2024-04-01T11:00:00+01:00",
      }
      adjacent_pd_shift = {
        "start" => "2024-04-01T08:00:00+01:00",
        "end" => "2024-04-01T09:00:00+01:00",
      }

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts([adjacent_pd_shift], shift_to_assign)).to eq([])
    end

    it "rejects shifts that start at the end time" do
      shift_to_assign = {
        start_datetime: "2024-04-01T09:00:00+01:00",
        end_datetime: "2024-04-01T11:00:00+01:00",
      }
      adjacent_pd_shift = {
        "start" => "2024-04-01T11:00:00+01:00",
        "end" => "2024-04-01T12:00:00+01:00",
      }

      pd = described_class.new(api_token: "foo")
      expect(pd.find_corresponding_shifts([adjacent_pd_shift], shift_to_assign)).to eq([])
    end
  end

  describe "#create_override" do
    it "sends an override request to PagerDuty" do
      schedule_id = "P999ABC"
      pagerduty_user_id = "foo"
      start_datetime = "2024-04-05T17:30:00+01:00"
      end_datetime = "2024-04-08T00:00:00+01:00"

      post_request = stub_request(:post, "https://api.pagerduty.com/schedules/P999ABC/overrides")
        .with(
          body: {
            override: {
              start: start_datetime,
              end: end_datetime,
              user: {
                id: pagerduty_user_id,
                type: "user_reference",
              },
            },
          }.to_json,
        ).to_return(status: 200, body: "", headers: {})

      pd = described_class.new(api_token: "foo")
      pd.create_override(schedule_id, pagerduty_user_id, start_datetime, end_datetime)

      expect(post_request).to have_been_requested
    end
  end
end
