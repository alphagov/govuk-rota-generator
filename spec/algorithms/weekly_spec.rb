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

  describe ".fill_slots!" do
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

  describe ".balance_slots" do
    let(:roles_config) { Roles.new(config: { foo: { value: 1, weekdays: true } }) }

    it "reallocates shifts to spread the shift weight more evenly" do
      underburdened_person = Person.new(
        email: "b@b.com",
        team: "Bar",
        can_do_roles: %i[foo],
        assigned_shifts: [],
        roles_config:,
      )
      overburdened_person = Person.new(
        email: "a@a.com",
        team: "Baz",
        can_do_roles: %i[foo],
        assigned_shifts: [
          { date: "01/04/2024", role: :foo },
          { date: "02/04/2024", role: :foo },
          { date: "03/04/2024", role: :foo },
          { date: "04/04/2024", role: :foo },
        ],
        roles_config:,
      )
      people = [underburdened_person, overburdened_person]

      described_class.balance_slots(people, roles_config)
      expect(underburdened_person.assigned_shifts).to eq([
        { date: "01/04/2024", role: :foo },
      ])
      expect(overburdened_person.assigned_shifts).to eq([
        { date: "02/04/2024", role: :foo },
        { date: "03/04/2024", role: :foo },
        { date: "04/04/2024", role: :foo },
      ])

      described_class.balance_slots(people, roles_config)
      expect(underburdened_person.assigned_shifts).to eq([
        { date: "01/04/2024", role: :foo },
        { date: "02/04/2024", role: :foo },
      ])
      expect(overburdened_person.assigned_shifts).to eq([
        { date: "03/04/2024", role: :foo },
        { date: "04/04/2024", role: :foo },
      ])
    end

    it "reallocates shifts in the middle too, not just the extremes" do
      underburdened_person = Person.new(
        email: "got_off_scott_free@b.com",
        team: "Bar",
        can_do_roles: %i[foo],
        assigned_shifts: [],
        forbidden_in_hours_days: [
          "03/04/2024",
          "04/04/2024",
          "05/04/2024",
        ],
        roles_config:,
      )
      overburdened_person = Person.new(
        email: "help_me@a.com",
        team: "Baz",
        can_do_roles: %i[foo],
        forbidden_in_hours_days: [
          "03/04/2024",
          "04/04/2024",
          "05/04/2024",
        ],
        assigned_shifts: [
          { date: "01/04/2024", role: :foo },
          { date: "02/04/2024", role: :foo },
        ],
        roles_config:,
      )
      overburdened_person_that_cannot_be_helped = Person.new(
        email: "cannot_help_me@a.com",
        team: "Baz",
        can_do_roles: %i[foo],
        assigned_shifts: [
          { date: "03/04/2024", role: :foo },
          { date: "04/04/2024", role: :foo },
          { date: "05/04/2024", role: :foo },
        ],
        roles_config:,
      )
      people = [underburdened_person, overburdened_person, overburdened_person_that_cannot_be_helped]

      described_class.balance_slots(people, roles_config)

      expect(underburdened_person.assigned_shifts).to eq([
        { date: "01/04/2024", role: :foo },
      ])
      expect(overburdened_person.assigned_shifts).to eq([
        { date: "02/04/2024", role: :foo },
      ])
    end
  end
end
