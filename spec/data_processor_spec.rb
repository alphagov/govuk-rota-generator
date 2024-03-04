require "csv"
require "data_processor"

RSpec.describe DataProcessor do
  describe ".combine_csvs" do
    it "combines two CSV files into one YML file" do
      responses_csv = "#{File.dirname(__FILE__)}/fixtures/data_processor/combine_csvs/responses.csv"
      people_csv = "#{File.dirname(__FILE__)}/fixtures/data_processor/combine_csvs/people.csv"

      filepath = "#{File.dirname(__FILE__)}/tmp/local.yml"
      File.delete(filepath) if File.exist? filepath

      described_class.combine_csvs(responses_csv:, people_csv:, filepath:)
      expect(File.read(filepath)).to eq(File.read("#{File.dirname(__FILE__)}/fixtures/data_processor/combine_csvs/rota_inputs.yml"))
    end
  end

  describe ".create_people_from_csv_data" do
    it "combines two CSV parsed inputs into one array of Person" do
      people_data = CSV.parse(<<~CSV, headers: true)
        Email,Eligible for in-hours primary?,Can do in-hours secondary?,Eligible for on-call primary?,Eligible for on-call secondary?,Should be scheduled for on-call?
        a@a.com,Yes,Yes,Yes,Yes,Yes
      CSV
      responses_data = CSV.parse(<<~CSV, headers: true)
        Timestamp,Email address,Have you been given an exemption from on call?,Do you have any non working days? [Non working day(s)],What team/area are you in (or will be in when this rota starts)?,"If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours",Week commencing 01/04/2024,Week commencing 08/04/2024,Need to elaborate on any of the above?
        timestamp,a@a.com,"","Wed,Fri",Platform,,"",Not available for on-call over the weekend
      CSV

      expect(Person).to receive(:new).with({
        email: "a@a.com",
        team: "Platform",
        non_working_days: %w[Wednesday Friday],
        forbidden_in_hours_days: [],
        forbidden_on_call_days: ["13/04/2024", "14/04/2024"],
        can_do_roles: %i[
          inhours_primary
          inhours_secondary
          inhours_primary_standby
          inhours_secondary_standby
          oncall_primary
          oncall_secondary
        ],
      })

      described_class.create_people_from_csv_data(people_data, responses_data)
    end

    it "assumes availability if the person hasn't provided availability responses" do
      people_data = CSV.parse(<<~CSV, headers: true)
        Email,Eligible for in-hours primary?,Can do in-hours secondary?,Eligible for on-call primary?,Eligible for on-call secondary?,Should be scheduled for on-call?
        a@a.com,Yes,Yes,Yes,Yes,Yes
      CSV
      responses_data = CSV.parse(<<~CSV, headers: true)
        Timestamp,Email address,Have you been given an exemption from on call?,Do you have any non working days? [Non working day(s)],What team/area are you in (or will be in when this rota starts)?,"If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours",Week commencing 01/04/2024,Week commencing 08/04/2024,Need to elaborate on any of the above?
      CSV

      expect(Person).to receive(:new).with({
        email: "a@a.com",
        team: "Unknown",
        non_working_days: [],
        forbidden_in_hours_days: [],
        forbidden_on_call_days: [],
        can_do_roles: %i[
          inhours_primary
          inhours_secondary
          inhours_primary_standby
          inhours_secondary_standby
          oncall_primary
          oncall_secondary
        ],
      })

      described_class.create_people_from_csv_data(people_data, responses_data)
    end
  end

  describe "#validate_responses" do
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

    def mock_csv_headers(headers)
      instance_double("Responses Data", headers:)
    end

    it "raises an exception if columns are not in expected structure" do
      responses_data = mock_csv_headers([
        "Timestampp", # deliberate typo
      ])

      expect { described_class.validate_responses(responses_data) }.to raise_exception(
        InvalidStructureException,
        "Expected 'Timestampp' to match '(?-mix:^Timestamp$)'",
      )
    end

    it "returns true if columns are in expected structure" do
      expect(described_class.validate_responses(mock_csv_headers(valid_headers))).to eq(true)
    end

    it "supports multiple 'Week commencing' columns" do
      responses_data = mock_csv_headers(valid_headers.insert(valid_headers.count - 1, [
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
      ]).flatten)

      expect(described_class.validate_responses(responses_data)).to eq(true)
    end

    it "raises an exception if the last column is missing" do
      responses_data = mock_csv_headers(valid_headers[0...-1])

      expect { described_class.validate_responses(responses_data) }.to raise_exception(
        InvalidStructureException,
        "Expected 'Week commencing 01/04/2024' to match '(?-mix:^Need to elaborate on any of the above\\?)'",
      )
    end

    it "raises an exception if the dates given aren't exactly 7 days apart" do
      responses_data = mock_csv_headers(valid_headers.insert(valid_headers.count - 1, [
        "Week commencing 08/04/2024",
        "Week commencing 16/04/2024", # should be 15th
      ]).flatten)

      expect { described_class.validate_responses(responses_data) }.to raise_exception(
        InvalidStructureException,
        "Expected 'Week commencing 16/04/2024' to be 'Week commencing 15/04/2024'",
      )
    end

    it "raises an exception if the first date isn't a Monday" do
      bad_headers = valid_headers
      bad_headers[valid_headers.count - 2] = "Week commencing 02/04/2024"
      responses_data = mock_csv_headers(bad_headers)

      expect { described_class.validate_responses(responses_data) }.to raise_exception(
        InvalidStructureException,
        "Expected column 'Week commencing 02/04/2024' to correspond to a Monday, but it's a Tuesday.",
      )
    end
  end
end
