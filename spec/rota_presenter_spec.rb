require "rota_presenter"

RSpec.describe RotaPresenter do
  describe "#to_csv" do
    it "outputs the rota as a CSV" do
      presenter = described_class.new(filepath: "#{File.dirname(__FILE__)}/fixtures/generated_rota.yml")

      expect(presenter.to_csv).to eq(
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
end
