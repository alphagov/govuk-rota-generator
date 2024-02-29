require "csv"
require_relative "../lib/data_processor"
require_relative "../lib/google_sheet"

AVAILABILITY_SHEET_ID = ARGV.first.match(/spreadsheets\/d\/([^\/]+)/)[1]
TECHNICAL_SUPPORT_SHEET_ID = "1OTVm_k6MDdCFN1EFzrKXWu4iIPI7uR9mssI8AMwn7lU"
RESPONSES_CSV = File.dirname(__FILE__) + "/../data/responses.csv"
PEOPLE_CSV = File.dirname(__FILE__) + "/../data/people.csv"
ROTA_INPUT_FILE = File.dirname(__FILE__) + "/../data/rota_inputs.yml"

puts "Fetching developer availability..."
responses = GoogleSheet.new.fetch(sheet_id: AVAILABILITY_SHEET_ID, filepath: RESPONSES_CSV)
puts "...downloaded to #{RESPONSES_CSV}"
puts "Validating data..."
DataProcessor.validate_responses(responses_csv: RESPONSES_CSV)
puts "...validated."

puts "Fetching 'Technical support' sheet..."
GoogleSheet.new.fetch(sheet_id: TECHNICAL_SUPPORT_SHEET_ID, range: "Technical support!A1:Z", filepath: PEOPLE_CSV)
puts "...downloaded to #{PEOPLE_CSV}."

puts "Merging the two datasets..."
DataProcessor.combine(responses_csv: RESPONSES_CSV, people_csv: PEOPLE_CSV, filepath: ROTA_INPUT_FILE)
puts "...merged to #{ROTA_INPUT_FILE}."
