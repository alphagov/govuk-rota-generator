require "yaml"
require "algorithms/weekly"
require "person"

RSpec.describe Algorithms::Weekly do
  let(:dates) do
    [
      "01/04/2024", # Mon
      "02/04/2024",
      "03/04/2024",
      "04/04/2024",
      "05/04/2024",
      "06/04/2024", # Sat
      "07/04/2024", # Sun
      "08/04/2024", # Mon
      "09/04/2024",
      "10/04/2024",
      "11/04/2024",
      "12/04/2024",
      "13/04/2024", # Sat
      "14/04/2024", # Sun
    ]
  end
  let(:roles_config) do
    {
      inhours_primary: {
        value: 1,
        weekdays: true,
        weeknights: false,
        weekends: false,
      },
    }
  end
  let(:people) { [person_a, person_b] }
  let(:person_a) { Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary]) }
  let(:person_b) { Person.new(email: "b@b.com", team: "Bar", can_do_roles: %i[inhours_primary]) }

  def stub_bank_holidays(bank_holidays = [])
    allow(described_class).to receive(:bank_holiday_dates).and_return(bank_holidays)
  end

  describe ".fill_slots!" do
    before { stub_bank_holidays }

    it "groups the shifts on a weekly basis" do
      described_class.fill_slots!(dates:, people:, roles_config:)
      expect(person_a.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
        { date: "05/04/2024", role: :inhours_primary },
      ])
      expect(person_b.assigned_shifts).to eq([
        { date: "08/04/2024", role: :inhours_primary },
        { date: "09/04/2024", role: :inhours_primary },
        { date: "10/04/2024", role: :inhours_primary },
        { date: "11/04/2024", role: :inhours_primary },
        { date: "12/04/2024", role: :inhours_primary },
      ])
    end

    it "fills in any gaps in availability for the week" do
      person_a = Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary], forbidden_in_hours_days: ["05/04/2024"])
      described_class.fill_slots!(people: [person_a, person_b], dates:, roles_config:)
      expect(person_a.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
      ])
      expect(person_b.assigned_shifts).to eq([
        { date: "05/04/2024", role: :inhours_primary },
        { date: "08/04/2024", role: :inhours_primary },
        { date: "09/04/2024", role: :inhours_primary },
        { date: "10/04/2024", role: :inhours_primary },
        { date: "11/04/2024", role: :inhours_primary },
        { date: "12/04/2024", role: :inhours_primary },
      ])
    end

    it "avoids scheduling someone in the first place if they can only commit to less than half the shift" do
      person_a = Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary], forbidden_in_hours_days: [
        "01/04/2024",
        "02/04/2024",
        "03/04/2024",
      ])
      person_b = Person.new(email: "b@b.com", team: "Bar", can_do_roles: %i[inhours_primary])
      described_class.fill_slots!(people: [person_a, person_b], dates:, roles_config:)

      # NOTE: that Person A has been assigned the shifts for week 2, rather than week 1, as they wouldn't
      # be able to fulfill most of week 1
      expect(person_a.assigned_shifts).to eq([
        { date: "08/04/2024", role: :inhours_primary },
        { date: "09/04/2024", role: :inhours_primary },
        { date: "10/04/2024", role: :inhours_primary },
        { date: "11/04/2024", role: :inhours_primary },
        { date: "12/04/2024", role: :inhours_primary },
      ])
      expect(person_b.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
        { date: "05/04/2024", role: :inhours_primary },
      ])
    end

    it "avoids scheduling two folks on the same team in the same week, for simultaneous roles (e.g. both in-hours roles)" do
      person_a = Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary inhours_secondary])
      person_b = Person.new(email: "b@b.com", team: "Foo", can_do_roles: %i[inhours_primary inhours_secondary])
      person_c = Person.new(email: "c@c.com", team: "Bar", can_do_roles: %i[inhours_primary inhours_secondary])
      roles_config = {
        inhours_primary: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        inhours_secondary: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
      }
      dates = [
        "01/04/2024", # Mon
        "02/04/2024",
        "03/04/2024",
        "04/04/2024",
        "05/04/2024",
        "06/04/2024", # Sat
        "07/04/2024", # Sun
      ]
      described_class.fill_slots!(people: [person_a, person_b, person_c], dates:, roles_config:)

      expect(person_a.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
        { date: "05/04/2024", role: :inhours_primary },
      ])
      expect(person_b.assigned_shifts).to eq([])
      expect(person_c.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_secondary },
        { date: "02/04/2024", role: :inhours_secondary },
        { date: "03/04/2024", role: :inhours_secondary },
        { date: "04/04/2024", role: :inhours_secondary },
        { date: "05/04/2024", role: :inhours_secondary },
      ])
    end

    it "doesn't care about scheduling two folks on the same team in the same week, for non-simultaneous roles (e.g. one in-hours, one on-call)" do
      person_a = Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary oncall_primary])
      person_b = Person.new(email: "b@b.com", team: "Foo", can_do_roles: %i[inhours_primary oncall_primary])
      person_c = Person.new(email: "c@c.com", team: "Bar", can_do_roles: %i[inhours_primary oncall_primary])
      roles_config = {
        inhours_primary: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        oncall_primary: {
          value: 1,
          weekdays: false,
          weeknights: true,
          weekends: false,
        },
      }
      dates = [
        "01/04/2024", # Mon
        "02/04/2024",
        "03/04/2024",
        "04/04/2024",
        "05/04/2024",
        "06/04/2024", # Sat
        "07/04/2024", # Sun
      ]
      described_class.fill_slots!(people: [person_a, person_b, person_c], dates:, roles_config:)

      expect(person_a.assigned_shifts).to eq([
        { date: "01/04/2024", role: :oncall_primary },
        { date: "02/04/2024", role: :oncall_primary },
        { date: "03/04/2024", role: :oncall_primary },
        { date: "04/04/2024", role: :oncall_primary },
        { date: "05/04/2024", role: :oncall_primary },
      ])
      expect(person_b.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
        { date: "05/04/2024", role: :inhours_primary },
      ])
      expect(person_c.assigned_shifts).to eq([])
    end
  end

  describe ".bank_holiday_dates" do
    it "flags all of the bank holiday dates from the given list of dates" do
      stub_request(:get, "https://www.gov.uk/bank-holidays.json").to_return(
        headers: { "Content-Type" => "application/json" },
        body: {
          "england-and-wales": {
            "division": "england-and-wales",
            "events": [
              {
                "title": "Early May bank holiday",
                "date": "2024-05-06",
                "notes": "",
                "bunting": true,
              },
            ],
          },
        }.to_json,
      )

      dates = [
        "05/05/2024",
        "06/05/2024", # Bank Holiday
        "07/05/2024",
      ]
      expect(described_class.bank_holiday_dates(dates)).to eq(["06/05/2024"])
    end
  end

  describe ".override_bank_holiday_daytime_shifts" do
    it "assigns the on-call person to the in-hours shift on bank holidays" do
      bank_holiday = "06/05/2024"
      stub_bank_holidays([bank_holiday])

      inhours_a = Person.new(email: "i@a.com", team: "Foo", can_do_roles: %i[inhours_primary])
      inhours_b = Person.new(email: "i@b.com", team: "Bar", can_do_roles: %i[inhours_secondary])
      oncall_a = Person.new(email: "o@a.com", team: "Baz", can_do_roles: %i[oncall_primary inhours_primary])
      oncall_b = Person.new(email: "o@b.com", team: "Bam", can_do_roles: %i[oncall_secondary inhours_secondary])
      inhours_a.assign(role: :inhours_primary, date: bank_holiday)
      inhours_b.assign(role: :inhours_secondary, date: bank_holiday)
      oncall_a.assign(role: :oncall_primary, date: bank_holiday)
      oncall_b.assign(role: :oncall_secondary, date: bank_holiday)
      people = [inhours_a, inhours_b, oncall_a, oncall_b]

      described_class.override_bank_holiday_daytime_shifts(people, [bank_holiday])
      expect(inhours_a.assigned_shifts).to eq([])
      expect(inhours_b.assigned_shifts).to eq([])
      expect(oncall_a.assigned_shifts).to eq([
        { date: bank_holiday, role: :oncall_primary },
        { date: bank_holiday, role: :inhours_primary },
      ])
      expect(oncall_b.assigned_shifts).to eq([
        { date: bank_holiday, role: :oncall_secondary },
        { date: bank_holiday, role: :inhours_secondary },
      ])
    end
  end
end
