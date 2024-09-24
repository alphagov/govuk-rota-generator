require "csv"
require "googleauth"
require "google/apis/sheets_v4"
require "json"

class GoogleSheetException < StandardError; end

class Tmp
  def read
    ENV.fetch("GOOGLE_SERVICE_ACCOUNT_KEY")
  end
end

class GoogleSheet
  def initialize(sheets_api: Google::Apis::SheetsV4::SheetsService.new, scope: :read)
    # https://developers.google.com/identity/protocols/oauth2/scopes#script
    scope = if scope == :read
              Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
            elsif scope == :write
              Google::Apis::SheetsV4::AUTH_SPREADSHEETS
            end

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: ENV.fetch("GOOGLE_SERVICE_ACCOUNT_KEY") ? Tmp.new : File.open("./google_service_account_key.json"),
      scope:,
    )
    authorizer.fetch_access_token!
    sheets_api.authorization = authorizer
    @sheets_api = sheets_api
  end

  def fetch(sheet_id:, range: "Form responses 1!A1:Z", filepath: nil)
    data = @sheets_api.get_spreadsheet_values(sheet_id, range).values

    if filepath
      File.write(filepath, data.map(&:to_csv).join)
    end

    data
  end

  def write(sheet_id:, csv:, range: "Auto-generated draft rota!A1:Z1000")
    data = Google::Apis::SheetsV4::ValueRange.new
    data.values = CSV.parse(csv)
    data.major_dimension = "ROWS" # https://developers.google.com/sheets/api/reference/rest/v4/Dimension
    data.range = range

    request = Google::Apis::SheetsV4::BatchUpdateValuesRequest.new
    request.data = [data]
    request.value_input_option = "USER_ENTERED" # https://developers.google.com/sheets/api/reference/rest/v4/ValueInputOption

    clear_request = Google::Apis::SheetsV4::BatchClearValuesRequest.new
    clear_request.ranges = [range]

    @sheets_api.batch_clear_values(sheet_id, clear_request) do |_response, error|
      raise GoogleSheetException, JSON.parse(error.body) if error

      puts "Cleared '#{range}' cells in Google Sheet #{sheet_id}."
    end

    @sheets_api.batch_update_values(sheet_id, request) do |response, error|
      raise GoogleSheetException, JSON.parse(error.body) if error

      puts "Wrote #{response.total_updated_cells} cells in Google Sheet #{sheet_id}."
    end
  end
end
