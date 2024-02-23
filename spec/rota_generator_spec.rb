require "rota_generator"
require "person"

RSpec.describe RotaGenerator do
  let(:fixture_path) { "#{File.dirname(__FILE__)}/fixtures/" }
  let(:roles_config) do
    {
      inhours_primary: {},
    }
  end

  it "raises an exception if a slot can't be filled" do
    people = [
      Person.new(email: "Dev Eloper", team: "Foo", can_do_roles: [:inhours_primary], forbidden_in_hours_days: ["01/04/2024"]),
    ]
    slots_to_fill = described_class.new.slots_to_fill(1, roles_config)

    expect { described_class.new.fill_slots(people, slots_to_fill) }
      .to output("WARNING: nobody is available for inhours_primary in week 1\n").to_stdout
  end

  it "avoids allocating forbidden_weeks" do
    people = [
      Person.new(email: "Busy Person",       team: "Foo", can_do_roles: [:inhours_primary], forbidden_weeks: [1, 3]),
      Person.new(email: "2nd Line Champion", team: "Bar", can_do_roles: [:inhours_primary], forbidden_weeks: []),
    ]
    slots_to_fill = described_class.new.slots_to_fill(3, roles_config)

    expect(described_class.new.fill_slots(people, slots_to_fill)).to eq([
      { week: 1, role: :inhours_primary, assignee: "2nd Line Champion" },
      { week: 2, role: :inhours_primary, assignee: "Busy Person" },
      { week: 3, role: :inhours_primary, assignee: "2nd Line Champion" },
    ])
  end

  it "spreads shift assignment evenly" do
    developer_a = Person.new(email: "Developer A", team: "Foo", can_do_roles: [:inhours_primary], forbidden_weeks: [])
    developer_b = Person.new(email: "Developer B", team: "Bar", can_do_roles: [:inhours_primary], forbidden_weeks: [])
    developer_c = Person.new(email: "Developer C", team: "Baz", can_do_roles: [:inhours_primary], forbidden_weeks: [])
    people = [developer_a, developer_b, developer_c]
    slots_to_fill = described_class.new.slots_to_fill(9, roles_config)

    described_class.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_c.assigned_shifts.count).to eq(3)
  end

  it "doesn't assign the same person to simultaneous shifts nor to shifts they can't do" do
    developer_a = Person.new(email: "Developer A", team: "Foo", can_do_roles: %i[inhours_primary some_other_role], forbidden_weeks: [])
    developer_b = Person.new(email: "Developer B", team: "Bar", can_do_roles: [:inhours_primary], forbidden_weeks: [])
    people = [developer_a, developer_b]
    roles_config = {
      inhours_primary: {},
      some_other_role: {},
    }
    slots_to_fill = described_class.new.slots_to_fill(3, roles_config)

    described_class.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_a.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:some_other_role])
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:inhours_primary])
  end

  it "can handle real datasets" do
    # Chosen seed is arbitrary, needed to ensure tests for random factor in sort are stable
    Randomiser.instance.set_seed(5959)
    rota_generator = described_class.new(csv: "#{fixture_path}/availability.csv")
    roles_config = {
      inhours_primary: {
        value: 1.4,
        weekdays: true,
        weeknights: false,
        weekends: false,
      },
      inhours_secondary: {
        value: 1.1,
        weekdays: true,
        weeknights: false,
        weekends: false,
      },
      inhours_primary_standby: {
        value: 0.75,
        weekdays: true,
        weeknights: false,
        weekends: false,
      },
      inhours_secondary_standby: {
        value: 0.75,
        weekdays: true,
        weeknights: false,
        weekends: false,
      },
      oncall_primary: {
        value: 2.5,
        weekdays: false,
        weeknights: true,
        weekends: true,
      },
      oncall_secondary: {
        value: 2,
        weekdays: false,
        weeknights: true,
        weekends: true,
      },
    }

    rota_generator.fill_slots(
      rota_generator.people,
      rota_generator.slots_to_fill(13, roles_config),
      roles_config,
    )

    expect(rota_generator.to_csv).to eq(File.read("#{fixture_path}/expected_output.csv"))
  end
end