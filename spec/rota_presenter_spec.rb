require "rota_presenter"

RSpec.describe RotaPresenter do
  describe "#initialize" do
    it "can take a filepath and roles arg" do
      rota_presenter = described_class.new(
        filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml",
      )

      expect(rota_presenter).to be_instance_of(described_class)
    end

    it "can take dates, people and roles directly" do
      rota_presenter = described_class.new(
        dates: ["01/04/2024"],
        people: [Person.new(email: "a@a.com", team: "Foo", can_do_roles: [])],
      )

      expect(rota_presenter).to be_instance_of(described_class)
    end

    it "raises an exception if invalid parameters provided" do
      bad_args = {
        people: [Person.new(email: "a@a.com", team: "Foo", can_do_roles: [])],
        # Notice that `dates` is missing
      }
      expect { described_class.new(bad_args) }.to raise_exception(BadRotaPresenterArgs, "Invalid parameters provided to RotaPresenter")
    end
  end

  describe "#to_yaml" do
    it "outputs the rota as YML" do
      presenter = described_class.new(filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml")
      expect(presenter.to_yaml).to eq(File.read("#{File.dirname(__FILE__)}/fixtures/generated_rota.yml"))
    end
  end

  describe "#to_csv_daily" do
    it "outputs the rota as a CSV" do
      presenter = described_class.new(filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml")

      expect(presenter.to_csv_daily).to eq(
        <<~CSV.chomp,
          date,inhours_primary,oncall_primary
          01/04/2024,A,B
          02/04/2024,A,B
          03/04/2024,A,B
          04/04/2024,A,C
          05/04/2024,B,C
          06/04/2024,"",C
          07/04/2024,"",C
          08/04/2024,B,C
          09/04/2024,B,C
          10/04/2024,B,C
          11/04/2024,B,C
          12/04/2024,B,C
          13/04/2024,"",C
          14/04/2024,"",C

        CSV
      )
    end
  end

  describe "#to_csv_weekly" do
    it "outputs the rota as a CSV, grouped by week, each role showing the person with the most shifts that week (and daily overrides provided in parentheses)" do
      presenter = described_class.new(filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml")

      expect(presenter.to_csv_weekly).to eq(
        <<~CSV.chomp,
          week,inhours_primary,oncall_primary
          01/04/2024-07/04/2024,A (B on 05/04/2024),"C (B on 01/04/2024, B on 02/04/2024, B on 03/04/2024)"
          08/04/2024-14/04/2024,B,C

        CSV
      )
    end
  end

  describe "#fairness_summary" do
    it "describes the fairness of the generated rota" do
      filepath = "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml"
      fixture_data = YAML.load_file(filepath, symbolize_names: true)
      people = fixture_data[:people].map { |person_data| Person.new(**person_data) }
      presenter = described_class.new(people:, dates: [])
      roles_config = {
        inhours_primary: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        oncall_primary: {
          value: 2,
          weekdays: false,
          weeknights: true,
          weekends: true,
        },
      }

      expect(presenter.fairness_summary(roles_config:)).to eq(
        <<~OUTPUT.chomp,
          C has 22 units of inconvenience, made up of 11 shifts including 11 oncall_primary.
          B has 12 units of inconvenience, made up of 9 shifts including 3 oncall_primary, 6 inhours_primary.
          A has 4 units of inconvenience, made up of 4 shifts including 4 inhours_primary.
        OUTPUT
      )
    end
  end
end
