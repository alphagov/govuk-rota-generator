require "yaml"
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
        weekdays: true,
        weeknights: false,
        weekends: false,
      },
    }
  end
  let(:people) { [person_a, person_b] }
  let(:person_a) { Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary]) }
  let(:person_b) { Person.new(email: "b@b.com", team: "Bar", can_do_roles: %i[inhours_primary]) }

  describe "#fill_slots" do
    it "avoids scheduling people who can't fill a certain role" do
      unqualified_person = Person.new(email: "unqualified@person.com", team: "Baz", can_do_roles: [])
      people = [person_a, unqualified_person]
      described_class.new(dates:, people:, roles_config:).fill_slots

      expect(unqualified_person.assigned_shifts).to eq([])
      expect(person_a.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
        { date: "05/04/2024", role: :inhours_primary },
        { date: "08/04/2024", role: :inhours_primary },
        { date: "09/04/2024", role: :inhours_primary },
        { date: "10/04/2024", role: :inhours_primary },
        { date: "11/04/2024", role: :inhours_primary },
        { date: "12/04/2024", role: :inhours_primary },
      ])
    end

    it "outputs a warning if nobody is available to do the shift" do
      generator = described_class.new(dates: ["01/04/2024"], people: [], roles_config:)
      expect { generator.fill_slots }.to output("NOBODY ABLE TO FILL inhours_primary on 01/04/2024\n").to_stdout
    end

    it "distributes shifts according to their value/weighting" do
      dates = [
        "01/04/2024",
        "02/04/2024",
        "03/04/2024",
        "04/04/2024",
        "05/04/2024",
      ]
      roles_config = {
        inhours_primary: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        inhours_secondary: {
          value: 0.5,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
      }
      person_a = Person.new(email: "a@a.com", team: "Foo", can_do_roles: %i[inhours_primary inhours_secondary])
      person_b = Person.new(email: "b@b.com", team: "Bar", can_do_roles: %i[inhours_primary inhours_secondary])
      person_c = Person.new(email: "c@c.com", team: "Baz", can_do_roles: %i[inhours_primary inhours_secondary])

      described_class.new(dates:, people: [person_a, person_b, person_c], roles_config:).fill_slots

      roles = Roles.new(config: roles_config)
      expect(roles.value_of_shifts(person_a.assigned_shifts)).to eq(2.5)
      expect(roles.value_of_shifts(person_b.assigned_shifts)).to eq(2.0)
      expect(roles.value_of_shifts(person_c.assigned_shifts)).to eq(3.0)

      expect(person_a.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_primary },
        { date: "04/04/2024", role: :inhours_primary },
        { date: "05/04/2024", role: :inhours_secondary },
      ])
      expect(person_b.assigned_shifts).to eq([
        { date: "01/04/2024", role: :inhours_secondary },
        { date: "02/04/2024", role: :inhours_secondary },
        { date: "03/04/2024", role: :inhours_primary },
      ])
      expect(person_c.assigned_shifts).to eq([
        { date: "02/04/2024", role: :inhours_primary },
        { date: "03/04/2024", role: :inhours_secondary },
        { date: "04/04/2024", role: :inhours_secondary },
        { date: "05/04/2024", role: :inhours_primary },
      ])
    end
  end

  describe "#write_rota" do
    it "writes data to a YML file" do
      filepath = "#{File.dirname(__FILE__)}/tmp/local.yml"
      File.delete(filepath) if File.exist? filepath

      generator = described_class.new(dates:, people:, roles_config:)
      generator.fill_slots
      generator.write_rota(filepath:)
      written_yaml = YAML.load_file(filepath, symbolize_names: true)

      expect(written_yaml).to match(
        dates:,
        roles: roles_config,
        people: instance_of(Array),
      )
    end
  end
end
