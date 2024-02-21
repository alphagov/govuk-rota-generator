require "csv_validator"

RSpec.describe CsvValidator do
  describe ".validate_columns" do
    let(:valid_headers) do
      [
        "Timestamp",
        "Email address",
        "Have you been given an exemption from on call?\n\nPlease select \"Yes\" only if you've opted out (with Senior Tech approval). Don't worry about checking the box if you're ineligible for on-call (e.g. Frontend Developer, or lack of prod access) - you'll be automatically opted out.",
        "Do you have any non working days? [Non working day(s)]",
        "What team/area are you in (or will be in when this rota starts)?",
        "If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours",
        "Week commencing 01/04/2024",
        "Need to elaborate on any of the above?",
      ]
    end

    it "raises an exception if columns are not in expected structure" do
      bad_headers = [
        "Timestampp", # deliberate typo
      ]

      expect { described_class.validate_columns([bad_headers]) }.to raise_exception(
        InvalidStructureException,
        "Expected 'Timestampp' to match '(?-mix:^Timestamp$)'",
      )
    end

    it "returns true if columns are in expected structure" do
      expect(described_class.validate_columns([valid_headers])).to eq(true)
    end

    it "supports multiple 'Week commencing' columns" do
      valid_headers_multiple_weeks = valid_headers.insert(valid_headers.count - 1, [
        "Week commencing 08/04/2024",
        "Week commencing 15/04/2024",
        "Week commencing 22/04/2024",
        "Week commencing 29/04/2024",
        "Week commencing 06/05/2024",
        "Week commencing 13/05/2024",
        "Week commencing 20/05/2024",
        "Week commencing 27/05/2024",
        "Week commencing 03/06/2024",
        "Week commencing 10/06/2024",
        "Week commencing 17/06/2024",
        "Week commencing 24/06/2024",
      ]).flatten

      expect(described_class.validate_columns([valid_headers_multiple_weeks])).to eq(true)
    end

    it "raises an exception if the last column is missing" do
      bad_headers = valid_headers[0...-1]

      expect { described_class.validate_columns([bad_headers]) }.to raise_exception(
        InvalidStructureException,
        "Expected 'Week commencing 01/04/2024' to match '(?-mix:^Need to elaborate on any of the above\\?)'",
      )
    end
  end
end
