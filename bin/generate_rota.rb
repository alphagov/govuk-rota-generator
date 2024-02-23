require_relative "../lib/rota_generator"
require_relative "../lib/fairness_calculator"

# TODO take these as CLI args
FIRST_DATE = "01/04/2024"
LAST_DATE = "30/06/2024"
DATA_YML = File.dirname(__FILE__) + "/../data/combined.yml"

ROLES_CONFIG = {
  inhours_primary: {
    value: 1.4,
    weekdays: true,
    weeknights: false,
    weekends: false,
  },
  inhours_secondary: {
    value: 1.1,
    weekdays: true,
    weeknights: false,
    weekends: false,
  },
  inhours_primary_standby: {
    value: 0.75,
    weekdays: true,
    weeknights: false,
    weekends: false,
  },
  inhours_secondary_standby: {
    value: 0.75,
    weekdays: true,
    weeknights: false,
    weekends: false,
  },
  oncall_primary: {
    value: 2.5,
    weekdays: false,
    weeknights: true,
    weekends: true,
  },
  oncall_secondary: {
    value: 2,
    weekdays: false,
    weeknights: true,
    weekends: true,
  },
}

generator = RotaGenerator.new(yml: DATA_YML)
people = generator.people

dates = [FIRST_DATE]
tmp = FIRST_DATE
while Date.parse(tmp).strftime("%d/%m/%Y") != LAST_DATE
  tmp = (Date.parse(tmp) + 1).strftime("%d/%m/%Y")
  dates << tmp
end

generator.fill_slots(
  people,
  generator.slots_to_fill(dates, ROLES_CONFIG),
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
