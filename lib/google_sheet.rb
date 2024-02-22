require "googleauth"
require "google/apis/sheets_v4"

class MissingSheetException < StandardError; end
class InvalidSheetStructureException < StandardError; end

class GoogleSheet
  def initialize(sheets_api: Google::Apis::SheetsV4::SheetsService.new)
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open("./google_service_account_key.json"),
      # https://developers.google.com/identity/protocols/oauth2/scopes#script
      scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY,
    )
    authorizer.fetch_access_token!
    sheets_api.authorization = authorizer
    @sheets_api = sheets_api
  end

  def fetch(sheet_id:, range: "Form responses 1!A1:Z")
    @sheets_api.get_spreadsheet_values(sheet_id, range)
  end
end
