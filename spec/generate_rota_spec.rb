require "generate_rota"
require "person"

RSpec.describe GenerateRota do
  let(:fixture_path) { "#{File.dirname(__FILE__)}/fixtures/" }
  let(:roles_config) do
    {
      some_role: {},
    }
  end

  it "raises an exception if a slot can't be filled" do
    people = [
      Person.new(name: "Dev Eloper", team: "Foo", can_do_roles: [:some_role], forbidden_weeks: [1]),
    ]
    slots_to_fill = described_class.new.slots_to_fill(1, roles_config)

    expect { described_class.new.fill_slots(people, slots_to_fill) }.to raise_exception(CannotFillSlotException)
  end

  it "avoids allocating forbidden_weeks" do
    people = [
      Person.new(name: "Busy Person",       team: "Foo", can_do_roles: [:some_role], forbidden_weeks: [1, 3]),
      Person.new(name: "2nd Line Champion", team: "Bar", can_do_roles: [:some_role], forbidden_weeks: []),
    ]
    slots_to_fill = described_class.new.slots_to_fill(3, roles_config)

    expect(described_class.new.fill_slots(people, slots_to_fill)).to eq([
      { week: 1, role: :some_role, assignee: "2nd Line Champion" },
      { week: 2, role: :some_role, assignee: "Busy Person" },
      { week: 3, role: :some_role, assignee: "2nd Line Champion" },
    ])
  end

  it "spreads shift assignment evenly" do
    developer_a = Person.new(name: "Developer A", team: "Foo", can_do_roles: [:some_role], forbidden_weeks: [])
    developer_b = Person.new(name: "Developer B", team: "Bar", can_do_roles: [:some_role], forbidden_weeks: [])
    developer_c = Person.new(name: "Developer C", team: "Baz", can_do_roles: [:some_role], forbidden_weeks: [])
    people = [developer_a, developer_b, developer_c]
    slots_to_fill = described_class.new.slots_to_fill(9, roles_config)

    described_class.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_c.assigned_shifts.count).to eq(3)
  end

  it "doesn't assign the same person to simultaneous shifts nor to shifts they can't do" do
    developer_a = Person.new(name: "Developer A", team: "Foo", can_do_roles: %i[some_role some_other_role], forbidden_weeks: [])
    developer_b = Person.new(name: "Developer B", team: "Bar", can_do_roles: [:some_role], forbidden_weeks: [])
    people = [developer_a, developer_b]
    roles_config = {
      some_role: {},
      some_other_role: {},
    }
    slots_to_fill = described_class.new.slots_to_fill(3, roles_config)

    described_class.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_a.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:some_other_role])
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:some_role])
  end

  # it "can handle real datasets" do
  #   rota_generator = described_class.new(csv: "#{fixture_path}/availability.csv")
  #   roles_config = {
  #     inhours_primary: {
  #       value: 1.4,
  #     },
  #     inhours_secondary: {
  #       value: 1.1,
  #     },
  #     inhours_primary_standby: {
  #       value: 0.75,
  #     },
  #     inhours_secondary_standby: {
  #       value: 0.75,
  #     },
  #     inhours_shadow: {
  #       value: 0,
  #       optional: true,
  #     },
  #     oncall_primary: {
  #       value: 2.5,
  #     },
  #     oncall_secondary: {
  #       value: 2,
  #     },
  #   }
  #   rota_generator.fill_slots(
  #     rota_generator.people,
  #     rota_generator.slots_to_fill(13, roles_config),
  #     roles_config,
  #   )

  #   expect(rota_generator.to_csv).to eq(File.read("#{fixture_path}/expected_output.csv"))
  # end

  it "can do all the super cool things" do
    rota_generator = described_class.new(csv: "#{fixture_path}/availability.csv")
    roles_config = {
      inhours_primary: {
        value: 1.4,
      },
      inhours_secondary: {
        value: 1.1,
      },
      inhours_primary_standby: {
        value: 0.75,
      },
      inhours_secondary_standby: {
        value: 0.75,
      },
      inhours_shadow: {
        value: 0,
        optional: true,
      },
      oncall_primary: {
        value: 2.5,
      },
      oncall_secondary: {
        value: 2,
      },
    }
    rota_generator.fill_slots(
      rota_generator.people,
      rota_generator.slots_to_fill(3, roles_config),
      roles_config,
    )
    puts "ATOM WAS COOL #{rota_generator.to_csv}"
    expect(rota_generator.to_csv).to eq(7)
  end
end
