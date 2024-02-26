require "csv"
require_relative "../lib/google_sheet"
require_relative "../lib/csv_validator"

AVAILABILITY_SHEET_ID = "1YV0e18wP0g3RsG146osvJLostYZgL9XS2jDGLQEgm2Q"
TECHNICAL_SUPPORT_SHEET_ID = "1OTVm_k6MDdCFN1EFzrKXWu4iIPI7uR9mssI8AMwn7lU"
RESPONSES_CSV = File.dirname(__FILE__) + "/../data/responses.csv"
PEOPLE_CSV = File.dirname(__FILE__) + "/../data/people.csv"
COMBINED_CSV = File.dirname(__FILE__) + "/../data/combined.csv"

# THE AIM IS TO CONVERT TWO CSVs INTO THE FORMAT govuk-rota-generators UNDERSTANDS, i.e.
#
# email,team,can_do_inhours_primary,can_do_inhours_secondary,can_do_inhours_primary_standby,can_do_inhours_secondary_standby,can_do_oncall_primary,can_do_oncall_secondary,forbidden_weeks
# Oswaldo Bonham,Platform Health,yes,yes,no,yes,yes,yes,yes,
#
class CombineCSVs
  def combined_data
    people_data = people
    responses_data = responses
    validate_combined_data(people_data, responses_data)

    combined = people_data.map do |row|
      response = responses_data.find { |response| response[:email] == row[:email] }
      if response
        merge_datasets(row, response)
      else
        nil
      end
    end

    combined.compact # remove non-responders
  end

  # Input is a CSV with headings like this:
  #
  # Email,Role,Contractor?,Role allows doing in-hours?,Can do in-hours secondary?,
  # Eligible for in-hours primary?,Role allows doing on-call?
  # Eligible for on-call primary?,Eligible for on-call secondary?
  # Exempt from on-call duties?,Should be scheduled for on-call?
  # Works Mondays?,Works Tuesdays?,Works Wednesdays?,Works Thursdays?,Works Fridays?
  #
  # Example row when converted to hash:
  # {"Email"=>"Foo Bar", "Role"=>"Junior Software Developer", "Contractor?"=>"No", "Role allows doing in-hours?"=>"Yes", "Can do in-hours secondary?"=>"No", "Eligible for in-hours primary?"=>"No", "Role allows doing on-call?"=>"No", "Eligible for on-call primary?"=>"No", "Eligible for on-call secondary?"=>"No", "Exempt from on-call duties?"=>"N/A", "Should be scheduled for on-call?"=>"No", "Works Mondays?"=>"Yes", "Works Tuesdays?"=>"Yes", "Works Wednesdays?"=>"Yes", "Works Thursdays?"=>"Yes", "Works Fridays?"=>"Yes"}
  #
  # Output from this method looks like:
  # {:email=>"Foo Bar", :team=>nil, :can_do_inhours_primary=>false, :can_do_inhours_secondary=>false, :can_do_inhours_primary_standby=>false, :can_do_inhours_secondary_standby=>false, :can_do_oncall_primary=>false, :can_do_oncall_secondary=>false, :forbidden_weeks=>nil}
  def people
    csv = CSV.read(File.dirname(__FILE__) + "/../data/people.csv", headers: true)

    data = csv.each.with_index(1).map do |row, index|
      tmp_data = row.to_h
      {
        email: tmp_data["Email"],
        team: nil, # This will be populated in another step
        can_do_inhours_primary: tmp_data["Eligible for in-hours primary?"] == "Yes",
        can_do_inhours_secondary: tmp_data["Can do in-hours secondary?"] == "Yes",
        can_do_inhours_primary_standby: tmp_data["Eligible for in-hours primary?"] == "Yes",
        can_do_inhours_secondary_standby: tmp_data["Can do in-hours secondary?"] == "Yes",
        can_do_oncall_primary: tmp_data["Should be scheduled for on-call?"] == "Yes",
        can_do_oncall_secondary: tmp_data["Should be scheduled for on-call?"] == "Yes", # TODO - currently no way of distinguishing people who are new to on call
        forbidden_weeks: nil, # This will be populated in another step
      }
    end
    data.reject { |row| row[:email].nil? } # there's a blank row between the header and the real data
  end

  # Input is a CSV with headings like this:
  #
  # Timestamp,Email address,What team will you be on? (team),
  # "If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours",
  # Do you have any non working days? [Non working day(s)],
  # Week 1 (03/04/23 - 09/04/23),Week 2 (10/04/23 - 16/04/23),Week 3 (17/04/23 - 23/04/23),Week 4 (24/04/23 - 30/04/23),Week 5 (01/05/23 - 07/05/23),Week 6 (08/05/23 - 14/05/23),Week 7 (15/05/23 - 21/05/23),Week 8 (22/05/23 - 28/05/23),Week 9 (29/05/23 - 04/06/23),Week 10 (05/06/23 - 11/06/23),Week 11 (12/06/23 - 18/06/23),Week 12 (19/06/23 - 25/06/23),Week 13 (26/06/23 - 02/07/23),Need to elaborate on any of the above?
  def responses
    csv = CSV.read(File.dirname(__FILE__) + "/../data/responses.csv", headers: true)

    # Mappings:
    # First week: "Week 1 (03/04/23 - 09/04/23)"
    # Second week: "Week 2 (10/04/23 - 16/04/23)"
    # ... and so on
    #Week 3 (17/04/23 - 23/04/23),Week 4 (24/04/23 - 30/04/23),Week 5 (01/05/23 - 07/05/23),Week 6 (08/05/23 - 14/05/23),Week 7 (15/05/23 - 21/05/23),Week 8 (22/05/23 - 28/05/23),Week 9 (29/05/23 - 04/06/23),Week 10 (05/06/23 - 11/06/23),Week 11 (12/06/23 - 18/06/23),Week 12 (19/06/23 - 25/06/23),Week 13 (26/06/23 - 02/07/23)
    #
    # Response for each week is either `nil`, or some combination of:
    # "Not available for in-hours, Not available for on-call weekday nights, Not available for on-call over the weekend"
    week_headers = csv.headers.select { |header| header.match(/^Week commencing/) }

    csv.each.with_index(1).map do |row, index|
      tmp_data = row.to_h

      limited_weeks = week_headers.each_with_index.map do |header, index|
        week_obj = {
          week: (index + 1),
          limitations: nil,
        }

        unless tmp_data[header].empty?
          week_obj[:limitations] = {
            no_in_hours: !tmp_data[header].match(/Not available for in-hours/).nil?,
            no_oncall_weekdays: !tmp_data[header].match(/Not available for on-call weekday nights/).nil?,
            no_oncall_weekend: !tmp_data[header].match(/Not available for on-call over the weekend/).nil?,
          }
        end
        week_obj
      end

      {
        email: tmp_data["Email address"],
        team: tmp_data["What team will you be on? (team)"],
        limited_weeks: limited_weeks,
      }
    end
  end

private

  def validate_combined_data(people_data, responses_data)
    people_names = people_data.map { |row| row[:email] }
    responses_names = responses_data.map { |row| row[:email] }

    unrecognised_responses = responses_names - people_names
    unless unrecognised_responses.count.zero?
      raise "Unrecognised names in responses: #{unrecognised_responses}"
    end

    non_responders = people_names - responses_names
    unless non_responders.count.zero?
      puts "Warning - the following developers did not provide availability and will be omitted from the generated rota: #{non_responders}"
      puts "" # extra newline
    end
  end

  def merge_datasets(person, response)
    person[:team] = response[:team]

    # TODO: iterate. But for now, we'll class the entire week as forbidden
    # regardless of whether in-hours, on-call weekdays or on-call weekend were checked
    unless response[:limited_weeks].nil?
      forbidden_weeks = response[:limited_weeks].map do |week|
        if week[:limitations].nil?
          nil
        elsif (!person[:can_do_oncall_primary] && !person[:can_do_oncall_secondary])
          # some devs tick the "Not available for on-call" options even if they've opted out of on-call 'globally' (the "Should be scheduled for on-call?" cell in the "Technical support" sheet).
          # This would make _every_ week a 'forbidden week'.
          # We should therefore only look at the in-hours availability of these devs when determining forbidden weeks.
          week[:limitations][:no_in_hours] ? week[:week] : nil
        else
          week[:week]
        end
      end


      person[:forbidden_weeks] = forbidden_weeks.compact.join(",")
    end

    person
  end
end

puts "Fetching developer availability..."
responses = GoogleSheet.new.fetch(sheet_id: AVAILABILITY_SHEET_ID, filepath: RESPONSES_CSV)
puts "...downloaded to #{RESPONSES_CSV}"
puts "Validating data..."
CsvValidator.validate_columns(responses)
puts "...validated."

puts "Fetching 'Technical support' sheet..."
GoogleSheet.new.fetch(sheet_id: TECHNICAL_SUPPORT_SHEET_ID, range: "Technical support!A1:Z", filepath: PEOPLE_CSV)
puts "...downloaded to #{PEOPLE_CSV}."

puts "Combining data..."
generated_data = CombineCSVs.new.combined_data
# https://stackoverflow.com/a/17864876
column_names = generated_data.first.keys
s = CSV.generate do |csv|
  csv << column_names
  generated_data.each do |x|
    csv << x.values
  end
end
File.write(COMBINED_CSV, s)
puts "...data combined and stored in #{COMBINED_CSV}."
