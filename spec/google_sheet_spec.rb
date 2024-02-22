require "google_sheet"

RSpec.describe GoogleSheet do
  before do
    mock_authorizer = instance_double("Google Authorizer", fetch_access_token!: true)
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(mock_authorizer)
    allow(File).to receive(:open).with("./google_service_account_key.json").and_return("{}")
  end

  describe "#fetch" do
    let(:sheet_id) { "1sK8ktAnffewnfiewnfoewifnwoein" }
    let(:mock_sheets_api) do
      mock_sheets_api = instance_double("Google::Apis::SheetsV4::SheetsService")
      allow(mock_sheets_api).to receive(:authorization=)
      mock_sheets_api
    end

    it "returns data if sheet is found" do
      range = "SomeWorksheet!A1:Z"
      mock_response = %w[foo]
      allow(mock_sheets_api).to receive(:get_spreadsheet_values).with(sheet_id, range).and_return(mock_response)

      result = described_class.new(sheets_api: mock_sheets_api)
        .fetch(sheet_id:, range:)

      expect(result).to be(mock_response)
    end

    it "defaults to range 'Form responses 1!A1:Z' (the default worksheet name in spreadsheets linked to Forms)" do
      expect(mock_sheets_api).to receive(:get_spreadsheet_values).with(sheet_id, "Form responses 1!A1:Z")

      described_class.new(sheets_api: mock_sheets_api).fetch(sheet_id:)
    end
  end
end
