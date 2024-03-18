require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/time/zones"
require "yaml"

Time.zone = "Europe/London"

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

  def pagerduty_roles
    @config.select { |_key, config| config[:pagerduty] }
  end

  def start_datetime(date, role)
    parsed_date = Time.zone.parse(date)
    day_of_week = parsed_date.strftime("%A")
    start_of_day = (parsed_date + 9.5.hours).iso8601
    end_of_day = (parsed_date + 17.5.hours).iso8601

    if @config[role][:weeknights] && %w[Monday Tuesday Wednesday Thursday Friday].include?(day_of_week)
      end_of_day
    else
      start_of_day
    end
  end

  def end_datetime(date, role)
    parsed_date = Time.zone.parse(date)
    end_of_day = (parsed_date + 17.5.hours).iso8601
    start_of_next_day = (parsed_date + 1.day + 9.5.hours).iso8601

    @config[role][:weekdays] ? end_of_day : start_of_next_day
  end
end
