require "rota_presenter"

RSpec.describe RotaPresenter do
  let(:filepath) { "#{File.dirname(__FILE__)}/fixtures/#{rota}" }
  let(:rota) { "generated_rota.yml" }

  describe "#to_csv" do
    context "with summarised arg set to daily" do
      let(:summarised) { :daily }

      it "outputs the rota as a CSV, showing daily breakdown" do
        presenter = described_class.new(filepath:)

        expect(presenter.to_csv(summarised:)).to eq(
          <<~CSV.chomp,
            date,inhours_primary
            01/04/2024,A
            02/04/2024,B
            03/04/2024,A
            04/04/2024,B
            05/04/2024,A
            06/04/2024,
            07/04/2024,
            08/04/2024,B
            09/04/2024,A
            10/04/2024,B
            11/04/2024,A
            12/04/2024,B
            13/04/2024,
            14/04/2024,
          CSV
        )
      end
    end

    context "with summarised arg set to weekly" do
      let(:summarised) { :weekly }
      let(:rota) { "generated_rota_weekly.yml" }

      it "outputs the rota as a CSV, showing daily breakdown" do
        presenter = described_class.new(filepath:)

        expect(presenter.to_csv(summarised:)).to eq(
          <<~CSV.chomp,
            week,inhours_primary
            01/04/2024-07/04/2024,A (B on 05/04/2024)
            08/04/2024-14/04/2024,B
          CSV
        )
      end
    end
  end

  describe "#fairness_summary" do
    it "describes the fairness of the generated rota" do
      fixture_data = YAML.load_file(filepath, symbolize_names: true)
      people = fixture_data[:people].map { |person_data| Person.new(**person_data) }
      roles_config = Roles.new(config: fixture_data[:roles])

      expect(described_class.fairness_summary(people:, roles_config:)).to eq(
        <<~OUTPUT.chomp,
          A has 5 units of inconvenience, made up of 5 shifts including 5 inhours_primary.
            (They're available for [:inhours_primary])
          B has 5 units of inconvenience, made up of 5 shifts including 5 inhours_primary.
            (They're available for [:inhours_primary])
        OUTPUT
      )
    end
  end
end
