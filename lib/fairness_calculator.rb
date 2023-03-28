class FairnessCalculator
  attr_reader :roles_to_fill

  def initialize(roles_to_fill)
    @roles_to_fill = roles_to_fill
  end

  def weight_of_shifts(shifts)
    combined = shifts.reduce(0) do |sum, shift|
      value_of_shift = roles_to_fill.dig(shift[:role], :value) || 1
      sum + value_of_shift
    end
    combined.round(1)
  end
end
