require "yaml"

class Roles
  attr_reader :config

  def initialize(config: nil)
    @config = config || YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)
  end

  def types
    @config.keys
  end

  def by_type(types)
    roles = @config.select do |_, conf|
      types.map { |type| conf[type] }.any?
    end
    roles.map { |role_id, _| role_id }
  end

  def value_of_shifts(shifts)
    values = shifts.map do |shift|
      @config[shift[:role]][:value]
    end
    values.sum.round(2)
  end
end
