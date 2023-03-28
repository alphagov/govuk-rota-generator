require "csv"

# THE AIM IS TO CONVERT TWO CSVs INTO THE FORMAT govuk-rota-generators UNDERSTANDS, i.e.
#
# name,team,can_do_inhours_primary,can_do_inhours_secondary,can_do_inhours_shadow,can_do_inhours_primary_standby,can_do_inhours_secondary_standby,can_do_oncall_primary,can_do_oncall_secondary,forbidden_weeks
# Oswaldo Bonham,Platform Health,yes,yes,no,yes,yes,yes,yes,
#
class CombineCSVs
  def combined_data
    people_data = people
    responses_data = responses
    validate_combined_data(people_data, responses_data)

    combined = people_data.map do |row|
      response = responses_data.find { |response| response[:name] == row[:name] }
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
  # Name,Role,Contractor?,Role allows doing in-hours?,Can do in-hours secondary?,
  # Eligible for in-hours primary?,Role allows doing on-call?
  # Eligible for on-call primary?,Eligible for on-call secondary?
  # Exempt from on-call duties?,Should be scheduled for on-call?
  # Works Mondays?,Works Tuesdays?,Works Wednesdays?,Works Thursdays?,Works Fridays?
  #
  # Example row when converted to hash:
  # {"Name"=>"Foo Bar", "Role"=>"Junior Software Developer", "Contractor?"=>"No", "Role allows doing in-hours?"=>"Yes", "Can do in-hours secondary?"=>"No", "Eligible for in-hours primary?"=>"No", "Role allows doing on-call?"=>"No", "Eligible for on-call primary?"=>"No", "Eligible for on-call secondary?"=>"No", "Exempt from on-call duties?"=>"N/A", "Should be scheduled for on-call?"=>"No", "Works Mondays?"=>"Yes", "Works Tuesdays?"=>"Yes", "Works Wednesdays?"=>"Yes", "Works Thursdays?"=>"Yes", "Works Fridays?"=>"Yes"}
  #
  # Output from this method looks like:
  # {:name=>"Foo Bar", :team=>nil, :can_do_inhours_primary=>false, :can_do_inhours_secondary=>false, :can_do_inhours_shadow=>true, :can_do_inhours_primary_standby=>false, :can_do_inhours_secondary_standby=>false, :can_do_oncall_primary=>false, :can_do_oncall_secondary=>false, :forbidden_weeks=>nil}
  def people
    csv = CSV.read(File.dirname(__FILE__) + "/../data/people.csv", headers: true)

    data = csv.each.with_index(1).map do |row, index|
      tmp_data = row.to_h
      {
        name: tmp_data["Name"],
        team: nil, # This will be populated in another step
        can_do_inhours_primary: tmp_data["Eligible for in-hours primary?"] == "Yes",
        can_do_inhours_secondary: tmp_data["Can do in-hours secondary?"] == "Yes",
        can_do_inhours_shadow: tmp_data["Role allows doing in-hours?"] == "Yes" && tmp_data["Can do in-hours secondary?"] == "No",
        can_do_inhours_primary_standby: tmp_data["Eligible for in-hours primary?"] == "Yes",
        can_do_inhours_secondary_standby: tmp_data["Can do in-hours secondary?"] == "Yes",
        can_do_oncall_primary: tmp_data["Should be scheduled for on-call?"] == "Yes",
        can_do_oncall_secondary: tmp_data["Should be scheduled for on-call?"] == "Yes", # TODO - currently no way of distinguishing people who are new to on call
        forbidden_weeks: nil, # This will be populated in another step
      }
    end
    data.reject { |row| row[:name].nil? } # there's a blank row between the header and the real data
  end

  # Input is a CSV with headings like this:
  #
  # Timestamp,What is your name,What team will you be on? (team),
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
    week_headers = [
      "Week 1 (03/04/23 - 09/04/23)",
      "Week 2 (10/04/23 - 16/04/23)",
      "Week 3 (17/04/23 - 23/04/23)",
      "Week 4 (24/04/23 - 30/04/23)",
      "Week 5 (01/05/23 - 07/05/23)",
      "Week 6 (08/05/23 - 14/05/23)",
      "Week 7 (15/05/23 - 21/05/23)",
      "Week 8 (22/05/23 - 28/05/23)",
      "Week 9 (29/05/23 - 04/06/23)",
      "Week 10 (05/06/23 - 11/06/23)",
      "Week 11 (12/06/23 - 18/06/23)",
      "Week 12 (19/06/23 - 25/06/23)",
      "Week 13 (26/06/23 - 02/07/23)",
    ]

    csv.each.with_index(1).map do |row, index|
      tmp_data = row.to_h

      limited_weeks = week_headers.each_with_index.map do |header, index|
        week_obj = {
          week: (index + 1),
          limitations: nil,
        }
        unless tmp_data[header].nil?
          week_obj[:limitations] = {
            no_in_hours: !tmp_data[header].match(/Not available for in-hours/).nil?,
            no_oncall_weekdays: !tmp_data[header].match(/Not available for on-call weekday nights/).nil?,
            no_oncall_weekend: !tmp_data[header].match(/Not available for on-call over the weekend/).nil?,
          }
        end
        week_obj
      end

      {
        name: tmp_data["What is your name"],
        team: tmp_data["What team will you be on? (team)"],
        limited_weeks: limited_weeks,
      }
    end
  end

private

  def validate_combined_data(people_data, responses_data)
    people_names = people_data.map { |row| row[:name] }
    responses_names = responses_data.map { |row| row[:name] }

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
      person[:forbidden_weeks] = response[:limited_weeks].map { |week| week[:week] unless week[:limitations].nil? }.compact.join(",")
    end

    person
  end
end

generated_data = CombineCSVs.new.combined_data

# https://stackoverflow.com/a/17864876
column_names = generated_data.first.keys
s = CSV.generate do |csv|
  csv << column_names
  generated_data.each do |x|
    csv << x.values
  end
end
File.write(File.dirname(__FILE__) + "/../data/combined.csv", s)
