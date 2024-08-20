require "yaml"
require_relative "../lib/data_processor"
require_relative "../lib/google_sheet"
require_relative "../lib/rota_presenter"

ROTA_SHEET_ID = ARGV.first.match(/spreadsheets\/d\/([^\/]+)/)[1]
TMP_ROTA_CSV = "#{File.dirname(__FILE__)}/../data/tmp_rota.csv".freeze
TMP_ROTA_YML = "#{File.dirname(__FILE__)}/../data/tmp_rota.yml".freeze

roles_config = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

puts "Fetching rota..."
GoogleSheet.new.fetch(sheet_id: ROTA_SHEET_ID, range: "Manually tweaked rota!A1:Z", filepath: TMP_ROTA_CSV)
puts "...downloaded to #{TMP_ROTA_CSV}."

puts "Converting to YML..."
DataProcessor.parse_csv(rota_csv: TMP_ROTA_CSV, roles_config:, rota_yml_output: TMP_ROTA_YML)
puts "...saved to #{TMP_ROTA_YML}."

puts "Calculating fairness..."
summary = RotaPresenter.new(
  people: YAML.load_file(TMP_ROTA_YML, symbolize_names: true)[:people].map { |person_data| Person.new(**person_data) },
  dates: [],
).fairness_summary(roles_config:)

preamble = <<~PREAMBLE
  The following people have been assigned shifts according to their eligibility and availability
  (we have assumed 100% availability if they have not filled in the availability survey).
  We've attempted to assess the fairness of the assigned shifts in the summary below.
  When finding cover or arranging swaps, we should try to avoid burdening the folks higher up the list, instead
  drawing from folks near the bottom of the list, but be careful to assign only shifts they're actually
  eligible for - this is defined in:
  https://docs.google.com/spreadsheets/d/1uLW-T7VtGE4YKdCvzOvmq2KoeXgZMv-HOpt70HQnEcU/edit?gid=1844919656.

PREAMBLE

puts "Writing fairness calculator results to Google Sheets"
GoogleSheet.new(scope: :write).write(
  sheet_id: ROTA_SHEET_ID,
  range: "Fairness calculator!A1:Z1000",
  csv: (preamble + summary).split("\n").map { |str| "\"#{str}\"" }.join("\n"),
)
puts "Writing fairness calculator results below:"
puts ""
puts summary
