require "google_sheet"

RSpec.describe GoogleSheet do
  before do
    mock_authorizer = double("Google Authorizer", fetch_access_token!: true) # rubocop:disable RSpec/VerifiedDoubles
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(mock_authorizer)
  end

  let(:sheet_id) { "1sK8ktAnffewnfiewnfoewifnwoein" }
  let(:mock_sheets_api) do
    mock_sheets_api = instance_double(Google::Apis::SheetsV4::SheetsService)
    allow(mock_sheets_api).to receive(:authorization=)
    mock_sheets_api
  end

  def stub_google_service_account_key_file
    allow(File).to receive(:file?).with("./google_service_account_key.json").and_return(true)
    allow(File).to receive(:open).with("./google_service_account_key.json").and_return("{}")
  end

  describe "initialising class with google service account key" do
    it "uses ENV var if that exists" do
      stub_const("GoogleSheet::GOOGLE_SERVICE_ACCOUNT_KEY", "foo")
      expect { described_class.new(sheets_api: mock_sheets_api) }.not_to raise_exception
    end

    it "uses file if no ENV var exists" do
      stub_google_service_account_key_file
      expect { described_class.new(sheets_api: mock_sheets_api) }.not_to raise_exception
    end

    it "errors if no ENV var and no file exist" do
      expect { described_class.new(sheets_api: mock_sheets_api) }.to raise_exception(GoogleSheetException)
    end
  end

  describe "#fetch" do
    before { stub_google_service_account_key_file }

    it "returns data if sheet is found" do
      range = "SomeWorksheet!A1:Z"
      mock_response = instance_double(Google::Apis::SheetsV4::ValueRange, values: %w[foo])
      allow(mock_sheets_api).to receive(:get_spreadsheet_values).with(sheet_id, range).and_return(mock_response)

      result = described_class.new(sheets_api: mock_sheets_api)
        .fetch(sheet_id:, range:)

      expect(result).to be(mock_response.values)
    end

    it "defaults to range 'Form responses 1!A1:Z' (the default worksheet name in spreadsheets linked to Forms)" do
      allow(mock_sheets_api).to receive(:get_spreadsheet_values).and_return(
        instance_double(Google::Apis::SheetsV4::ValueRange, values: %w[foo]),
      )
      expect(mock_sheets_api).to receive(:get_spreadsheet_values).with(sheet_id, "Form responses 1!A1:Z")

      described_class.new(sheets_api: mock_sheets_api).fetch(sheet_id:)
    end

    it "saves the data as a CSV if filepath provided" do
      mock_value_range = instance_double(Google::Apis::SheetsV4::ValueRange, values:
        [
          %w[foo bar],
          %w[baz bash],
        ])
      allow(mock_sheets_api).to receive(:get_spreadsheet_values).and_return(mock_value_range)

      filepath = "#{File.dirname(__FILE__)}/tmp/local.csv"
      File.delete(filepath) if File.exist? filepath
      described_class.new(sheets_api: mock_sheets_api).fetch(sheet_id: "some sheet id", range: "some range", filepath:)
      expect(File.read(filepath)).to eq(
        <<~CSV,
          foo,bar
          baz,bash
        CSV
      )
    end
  end

  describe "#write" do
    before { stub_google_service_account_key_file }

    let(:range) { "SomeWorksheet!A1:Z" }

    it "clears the sheet before writing values" do
      expect(mock_sheets_api).to receive(:batch_clear_values).once.ordered
      expect(mock_sheets_api).to receive(:batch_update_values).once.ordered

      described_class.new(sheets_api: mock_sheets_api).write(sheet_id:, range:, csv: "foo,bar,baz")
    end

    it "raises GoogleException if exception is encountered upstream" do
      error = { "error" => "Permissions issue" }
      mock_exception = double("Google Sheet Exception", body: error.to_json) # rubocop:disable RSpec/VerifiedDoubles
      allow(mock_sheets_api).to receive(:batch_clear_values).and_yield(nil, mock_exception)
      expect { described_class.new(sheets_api: mock_sheets_api).write(sheet_id:, range:, csv: "foo,bar,baz") }.to raise_exception(GoogleSheetException)
    end
  end
end
