require "google_sheet"

RSpec.describe GoogleSheet do
  before do
    mock_authorizer = instance_double("Google Authorizer", fetch_access_token!: true)
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(mock_authorizer)
    allow(File).to receive(:open).with("./google_service_account_key.json").and_return("{}")
  end

  describe "#fetch" do
    it "returns data if sheet is found" do
      sheet_id = "1sK8ktAnffewnfiewnfoewifnwoein"
      range = "Form responses 1!A1:Z"
      mock_response = %w[foo]
      mock_sheets_api = instance_double("Google::Apis::SheetsV4::SheetsService")
      allow(mock_sheets_api).to receive(:authorization=)
      allow(mock_sheets_api).to receive(:get_spreadsheet_values).with(sheet_id, range).and_return(mock_response)

      result = described_class.new(sheets_api: mock_sheets_api)
        .fetch(sheet_id:, range:)

      expect(result).to be(mock_response)
    end
  end
end
