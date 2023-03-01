require "generate_rota"
require "person"

RSpec.describe GenerateRota do
  let(:fixture_path) { File.dirname(__FILE__) + "/fixtures/" }

  it "raises an exception if a slot can't be filled" do
    people = [
      Person.new(name: "Dev Eloper", team: "Foo", can_do_roles: [:some_role], forbidden_weeks: [1]),
    ]
    slots_to_fill = [
      { week: 1, role: :some_role },
    ]
    
    expect { GenerateRota.new.fill_slots(people, slots_to_fill) }.to raise_exception(CannotFillSlotException)
  end

  it "avoids allocating forbidden_weeks" do
    people = [
      Person.new(name: "Busy Person",       team: "Foo", can_do_roles: [:some_role], forbidden_weeks: [1, 3]),
      Person.new(name: "2nd Line Champion", team: "Bar", can_do_roles: [:some_role], forbidden_weeks: []),
    ]
    slots_to_fill = [
      { week: 1, role: :some_role },
      { week: 2, role: :some_role },
      { week: 3, role: :some_role },
    ]
    
    expect(GenerateRota.new.fill_slots(people, slots_to_fill)).to eq([
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
    slots_to_fill = [
      { week: 1, role: :some_role },
      { week: 2, role: :some_role },
      { week: 3, role: :some_role },
      { week: 4, role: :some_role },
      { week: 5, role: :some_role },
      { week: 6, role: :some_role },
      { week: 7, role: :some_role },
      { week: 8, role: :some_role },
      { week: 9, role: :some_role },
    ]

    GenerateRota.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_c.assigned_shifts.count).to eq(3)
  end

  it "doesn't assign the same person to simultaneous shifts nor to shifts they can't do" do
    developer_a = Person.new(name: "Developer A", team: "Foo", can_do_roles: [:some_role, :some_other_role], forbidden_weeks: [])
    developer_b = Person.new(name: "Developer B", team: "Bar", can_do_roles: [:some_role], forbidden_weeks: [])
    people = [developer_a, developer_b]
    slots_to_fill = [
      { week: 1, role: :some_role },
      { week: 1, role: :some_other_role },
      { week: 2, role: :some_role },
      { week: 2, role: :some_other_role },
      { week: 3, role: :some_role },
      { week: 3, role: :some_other_role },
    ]

    GenerateRota.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_a.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:some_other_role])
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:some_role])
  end

  it "generates a proportionally split rota according to the value of each role" do
    rota_generator = GenerateRota.new(csv: "#{fixture_path}/simple.csv")
    rota_generator.generate(
      weeks_to_generate: 2,
      roles_to_fill: {
        inhours_primary: {
        },
        inhours_secondary: {
        },
        inhours_primary_standby: {
        },
        inhours_secondary_standby: {
        },
        inhours_shadow: {
          # TODO: mark as optional
        },
        oncall_primary: {
        },
        oncall_secondary: {
        },
      }
    )

    expect(rota_generator.to_h).to eq([
      {:assignee=>"Developer A", :role=>:oncall_secondary, :week=>1},
      {:assignee=>"Developer B", :role=>:oncall_primary, :week=>1},
      {:assignee=>"Developer D", :role=>:inhours_secondary_standby, :week=>1},
      {:assignee=>"Developer E", :role=>:inhours_shadow, :week=>1},
      {:assignee=>"Developer F", :role=>:inhours_primary_standby, :week=>1},
      {:assignee=>"Developer G", :role=>:inhours_secondary, :week=>1},
      {:assignee=>"Developer H", :role=>:inhours_primary, :week=>1},
      {:assignee=>"Developer I", :role=>:inhours_secondary_standby, :week=>2},
      {:assignee=>"Developer A", :role=>:oncall_primary, :week=>2},
      {:assignee=>"Developer E", :role=>:inhours_shadow, :week=>2},
      {:assignee=>"Developer B", :role=>:inhours_secondary, :week=>2},
      {:assignee=>"Developer C", :role=>:oncall_secondary, :week=>2},
      {:assignee=>"Developer J", :role=>:inhours_primary_standby, :week=>2},
      {:assignee=>"Developer D", :role=>:inhours_primary, :week=>2},
    ])
  end

  it "can handle real datasets" do
    rota_generator = GenerateRota.new(csv: "#{fixture_path}/output.csv")
    rota_generator.generate(
      weeks_to_generate: 13,
      roles_to_fill: {
        inhours_primary: {
        },
        inhours_secondary: {
        },
        inhours_primary_standby: {
        },
        inhours_secondary_standby: {
        },
        inhours_shadow: {
          # TODO: mark as optional
        },
        oncall_primary: {
        },
        oncall_secondary: {
        },
      }
    )

    expect(rota_generator.to_csv).to eq("TBC")
  end
end
