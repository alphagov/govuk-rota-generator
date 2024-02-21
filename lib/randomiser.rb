require "singleton"

class Randomiser
  include Singleton

  def initialize
    @randomiser = Random.new
  end

  def set_seed(seed)
    @randomiser = Random.new(seed)
  end

  def next_float
    @randomiser.rand
  end
end
