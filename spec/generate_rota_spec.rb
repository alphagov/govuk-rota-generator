require "generate_rota"
require "person"

RSpec.describe GenerateRota do
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
end
