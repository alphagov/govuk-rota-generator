require "yaml"
require_relative "../lib/algorithms/weekly"
require_relative "../lib/google_sheet"
require_relative "../lib/person"
require_relative "../lib/rota_presenter"

yml = YAML.load_file(File.dirname(__FILE__) + "/../data/rota_inputs.yml", symbolize_names: true)
people = yml[:people].map { |person_data| Person.new(**person_data) }
dates = yml[:dates]
roles_config = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

Algorithms::Weekly.fill_slots!(dates:, people:, roles_config:)

<<<<<<< HEAD
presenter = RotaPresenter.new(dates:, people:, roles_config:)
=======
# Experimental. Can call the balance step multiple times to attempt to
# make rota more balanced.
prev_standard_deviation = 2000
standard_deviation = 1000
while standard_deviation < prev_standard_deviation
  "Running balancing step..."
  prev_standard_deviation = standard_deviation
  standard_deviation = RotaGenerator.balance_slots(people, Roles.new(config: roles_config))
end
puts "...maximised balancing."

rota_output_file = "#{File.dirname(__FILE__)}/../data/generated_rota.yml"
generator.write_rota(filepath: rota_output_file)
>>>>>>> 1ffa1c6 (WIP: Attempt to rebalance shifts with additional passes)

puts "Writing rota to YML locally..."
File.write("#{File.dirname(__FILE__)}/../data/generated_rota.yml", presenter.to_yaml)

SHEET_URL = ARGV.first
if SHEET_URL.nil?
  puts "All shifts allocated. See CSV below:"
  puts ""
  puts presenter.to_csv_weekly
  puts ""
  puts "You can automatically write this output to Google Sheet by providing a Google Sheet URL as a CLI arg."
else
  puts "Writing CSV to Google Sheets"
  SHEET_ID = SHEET_URL.match(/spreadsheets\/d\/([^\/]+)/)[1]
  GoogleSheet.new(scope: :write).write(sheet_id: SHEET_ID, csv: presenter.to_csv_weekly)
  puts "Draft rota visible in the relevant worksheet at https://docs.google.com/spreadsheets/d/#{SHEET_ID}/edit"
end
