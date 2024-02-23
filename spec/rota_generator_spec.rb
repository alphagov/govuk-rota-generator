require "rota_generator"
require "person"

RSpec.describe RotaGenerator do
  let(:fixture_path) { "#{File.dirname(__FILE__)}/fixtures/" }
  let(:roles_config) do
    {
      inhours_primary: {},
    }
  end

  it "warns if a slot can't be filled" do
    people = [
      Person.new(email: "Dev Eloper", team: "Foo", can_do_roles: [:inhours_primary], forbidden_in_hours_days: ["01/04/2024"]),
    ]
    slots_to_fill = described_class.new.slots_to_fill(["01/04/2024"], roles_config)

    expect { described_class.new.fill_slots(people, slots_to_fill) }
      .to output("WARNING: nobody is available for inhours_primary on 01/04/2024\n").to_stdout
  end

  it "avoids allocating forbidden dates" do
    dates_to_fill = ["01/04/2024", "02/04/2024", "03/04/2024"]
    people = [
      Person.new(email: "Busy.Person@digital.cabinet-office.gov.uk", team: "Foo", can_do_roles: [:inhours_primary], forbidden_in_hours_days: ["01/04/2024", "03/04/2024"]),
      Person.new(email: "Someone.Else@digital.cabinet-office.gov.uk", team: "Bar", can_do_roles: [:inhours_primary], forbidden_in_hours_days: []),
    ]
    slots_to_fill = described_class.new.slots_to_fill(dates_to_fill, roles_config)

    expect(described_class.new.fill_slots(people, slots_to_fill)).to eq([
      { date: "01/04/2024", role: :inhours_primary, assignee: "Someone Else" },
      { date: "02/04/2024", role: :inhours_primary, assignee: "Busy Person" },
      { date: "03/04/2024", role: :inhours_primary, assignee: "Someone Else" },
    ])
  end

  it "spreads shift assignment evenly" do
    dates_to_fill = [
      "01/04/2024",
      "02/04/2024",
      "03/04/2024",
      "04/04/2024",
      "05/04/2024",
      "06/04/2024",
      "07/04/2024",
      "08/04/2024",
      "09/04/2024",
    ]
    developer_a = Person.new(email: "Developer.A@digital.cabinet-office.gov.uk", team: "Foo", can_do_roles: [:inhours_primary])
    developer_b = Person.new(email: "Developer.B@digital.cabinet-office.gov.uk", team: "Bar", can_do_roles: [:inhours_primary])
    developer_c = Person.new(email: "Developer.C@digital.cabinet-office.gov.uk", team: "Baz", can_do_roles: [:inhours_primary])
    people = [developer_a, developer_b, developer_c]
    slots_to_fill = described_class.new.slots_to_fill(dates_to_fill, roles_config)

    described_class.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_c.assigned_shifts.count).to eq(3)
  end

  it "doesn't assign the same person to simultaneous shifts nor to shifts they can't do" do
    dates_to_fill = [
      "01/04/2024",
      "02/04/2024",
      "03/04/2024",
    ]
    developer_a = Person.new(email: "Developer.A@digital.cabinet-office.gov.uk", team: "Foo", can_do_roles: %i[inhours_primary inhours_secondary])
    developer_b = Person.new(email: "Developer.B@digital.cabinet-office.gov.uk", team: "Bar", can_do_roles: [:inhours_primary])
    people = [developer_a, developer_b]
    roles_config = {
      inhours_primary: {},
      inhours_secondary: {},
    }
    slots_to_fill = described_class.new.slots_to_fill(dates_to_fill, roles_config)

    described_class.new.fill_slots(people, slots_to_fill)

    expect(developer_a.assigned_shifts.count).to eq(3)
    expect(developer_a.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:inhours_secondary])
    expect(developer_b.assigned_shifts.count).to eq(3)
    expect(developer_b.assigned_shifts.map { |shift| shift[:role] }.uniq).to eq([:inhours_primary])
  end
end
