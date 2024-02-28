require "yaml"
require_relative "../lib/rota_generator"
require_relative "../lib/fairness_calculator"

INPUT_CSV = File.dirname(__FILE__) + "/../data/combined.csv"
WEEKS_TO_GENERATE = 13
ROLES_CONFIG = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

puts "We want to generate a rota of #{WEEKS_TO_GENERATE} weeks, with the following roles in each week: #{ROLES_CONFIG.keys.join(", ")}"
slots_to_fill = WEEKS_TO_GENERATE * ROLES_CONFIG.keys.count
generator = RotaGenerator.new(csv: INPUT_CSV)

puts "There are #{slots_to_fill} slots to fill, and #{generator.people.count} people on the rota."
puts "Each person therefore needs to take an average of #{slots_to_fill / generator.people.count.to_f} slot(s)."
puts ""
generator.fill_slots(
  generator.people,
  generator.slots_to_fill(WEEKS_TO_GENERATE, ROLES_CONFIG),
  ROLES_CONFIG,
)
puts "All shifts allocated. See CSV below:"
puts ""
puts generator.to_csv
puts ""
puts "Checking fairness of spread:"
fairness_calculator = FairnessCalculator.new(ROLES_CONFIG)
generator.people.sort_by { |person| fairness_calculator.weight_of_shifts(person.assigned_shifts) }.reverse.each do |person|
  shift_types = person.assigned_shifts.map { |shift| shift[:role] }.uniq
  shift_totals = shift_types.map do |role|
    shift_count = person.assigned_shifts.select { |shift| shift[:role] == role }.count
    "#{shift_count} #{role}"
  end
  puts "#{person.email} has been allocated #{sprintf('%.1f', fairness_calculator.weight_of_shifts(person.assigned_shifts))} units of inconvenience (#{person.assigned_shifts.count} shifts made up of #{shift_totals.join(',')})"
end
