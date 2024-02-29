require "rota_presenter"

RSpec.describe RotaPresenter do
  describe "#initialize" do
    it "can take a filepath and roles arg" do
      described_class.new(filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml")
    end

    it "can take dates, people and roles directly" do
      described_class.new(
        dates: ["01/04/2024"],
        people: [Person.new(email: "a@a.com", team: "Foo", can_do_roles: [])],
      )
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
          04/04/2024,A,B
          05/04/2024,B,B
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
    it "outputs the rota as a CSV, grouped by week" do
      presenter = described_class.new(filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml")

      expect(presenter.to_csv_weekly).to eq(
        <<~CSV.chomp,
          week,inhours_primary,oncall_primary
          01/04/2024-07/04/2024,A (B on 05/04/2024),"B (C on 06/04/2024, C on 07/04/2024)"
          08/04/2024-14/04/2024,B,C

        CSV
      )
    end
  end
end
