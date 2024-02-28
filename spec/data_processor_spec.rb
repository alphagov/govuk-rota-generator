require "csv"
require "data_processor"

RSpec.describe DataProcessor do
  describe ".combine" do
    it "combines two CSV files into one YML file" do
      responses_csv = "#{File.dirname(__FILE__)}/fixtures/responses.csv"
      people_csv = "#{File.dirname(__FILE__)}/fixtures/people.csv"

      filepath = "#{File.dirname(__FILE__)}/tmp/local.yml"
      File.delete(filepath) if File.exist? filepath

      described_class.combine(responses_csv:, people_csv:, filepath:)
      expect(File.read(filepath)).to eq(File.read("#{File.dirname(__FILE__)}/fixtures/rota_inputs.yml"))
    end
  end

  describe ".combine_raw" do
    it "combines two CSV parsed inputs into one array of Person" do
      people_data = CSV.parse(<<~CSV, headers: true)
        Email,Eligible for in-hours primary?,Can do in-hours secondary?,Eligible for on-call primary?,Eligible for on-call secondary?,Should be scheduled for on-call?
        a@a.com,Yes,Yes,Yes,Yes,Yes
      CSV
      responses_data = CSV.parse(<<~CSV, headers: true)
        Email address,What team/area are you in (or will be in when this rota starts)?,Do you have any non working days? [Non working day(s)],Week commencing 01/04/2024,Week commencing 08/04/2024
        a@a.com,Platform,"Wed,Fri","",Not available for on-call over the weekend
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

      described_class.combine_raw(people_data, responses_data)
    end
  end
end
