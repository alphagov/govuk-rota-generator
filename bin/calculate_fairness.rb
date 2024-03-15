require "yaml"
require_relative "../lib/data_processor"
require_relative "../lib/google_sheet"
require_relative "../lib/rota_presenter"

ROTA_SHEET_ID = ARGV.first.match(/spreadsheets\/d\/([^\/]+)/)[1]
TMP_ROTA_CSV = File.dirname(__FILE__) + "/../data/tmp_rota.csv"
TMP_ROTA_YML = File.dirname(__FILE__) + "/../data/tmp_rota.yml"

roles_config = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

puts "Fetching rota..."
GoogleSheet.new.fetch(sheet_id: ROTA_SHEET_ID, range: "Auto-generated draft rota!A1:Z", filepath: TMP_ROTA_CSV)
puts "...downloaded to #{TMP_ROTA_CSV}."

puts "Converting to YML..."
DataProcessor.parse_csv(rota_csv: TMP_ROTA_CSV, roles_config:, rota_yml_output: TMP_ROTA_YML)
puts "...saved to #{TMP_ROTA_YML}."

puts "Fairness calculator"
puts RotaPresenter.new(
  people: YAML.load_file(TMP_ROTA_YML, symbolize_names: true)[:people].map { |person_data| Person.new(**person_data) },
  dates: [],
).fairness_summary(roles_config:)
