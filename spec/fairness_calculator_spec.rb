require "fairness_calculator"

RSpec.describe FairnessCalculator do
  describe "#weight_of_shifts" do
    it "returns the combined weight of all shifts undertaken by the person" do
      calculator = FairnessCalculator.new({
        some_role: {
          value: 1.1,
        },
        some_other_role: {
          value: 0.3,
        },
      })
      expect(calculator.weight_of_shifts([
        { week: 1, role: :some_role },
        { week: 3, role: :some_other_role },
      ])).to eq(1.4)
    end

    it "defaults to value of '1' if value is not specified" do
      calculator = FairnessCalculator.new({
        some_role: {},
        some_other_role: {
          value: 0.3,
        },
      })
      expect(calculator.weight_of_shifts([
        { week: 1, role: :some_role },
        { week: 3, role: :some_other_role },
      ])).to eq(1.3)
    end

    it "defaults to value of '1' if role isn't specified" do
      calculator = FairnessCalculator.new({})
      expect(calculator.weight_of_shifts([
        { week: 1, role: :some_role },
        { week: 3, role: :some_other_role },
      ])).to eq(2)
    end
  end
end
