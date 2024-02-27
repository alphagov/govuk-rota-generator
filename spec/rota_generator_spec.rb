require "rota_generator"
require "person"

RSpec.describe RotaGenerator do
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
      },
    }
  end
  let(:people) { [person_a, person_b] }
  let(:person_a) { Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary]) }
  let(:person_b) { Person.new(email: "b@b.com", team: "Bar", can_do_roles: %i[inhours_primary]) }

  it "alternates the shifts on a daily basis by default" do
    described_class.new(dates:, people:, roles_config:).fill_slots
    expect(person_a.assigned_shifts).to eq([
      { date: "01/04/2024", role: :inhours_primary },
      { date: "03/04/2024", role: :inhours_primary },
      { date: "05/04/2024", role: :inhours_primary },
      { date: "09/04/2024", role: :inhours_primary },
      { date: "11/04/2024", role: :inhours_primary },
    ])
    expect(person_b.assigned_shifts).to eq([
      { date: "02/04/2024", role: :inhours_primary },
      { date: "04/04/2024", role: :inhours_primary },
      { date: "08/04/2024", role: :inhours_primary },
      { date: "10/04/2024", role: :inhours_primary },
      { date: "12/04/2024", role: :inhours_primary },
    ])
  end

  it "groups the shifts on a weekly basis if configured to" do
    described_class.new(dates:, people:, roles_config:).fill_slots(group_weekly: true)
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

  context "person A has a non-working day Friday" do
    let(:person_a) { Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary], non_working_days: %w[Friday]) }

    it "reassigns their Friday to another person" do
      described_class.new(dates:, people:, roles_config:).fill_slots(group_weekly: true)
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
  end
end
