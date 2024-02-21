class InvalidStructureException < StandardError; end

class CsvValidator
  def self.validate_columns(csv)
    first_columns_regexes = [
      /^Timestamp$/,
      /^Email address$/,
      /^Have you been given an exemption from on call\?/,
      /^Do you have any non working days\?/,
      /^What team\/area are you in/,
      /^If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours/,
    ]
    week_commencing_regex = /^Week commencing \d+{2}\/\d{2}\/\d{4}$/
    last_column_regex = /^Need to elaborate on any of the above\?/

    columns = csv.first
    first_columns = columns.shift(first_columns_regexes.count).each_with_index.map do |column, index|
      { regex: first_columns_regexes[index], value: column }
    end
    last_column = [columns.pop].map { |column| { regex: last_column_regex, value: column } }
    week_columns = columns.map { |column| { regex: week_commencing_regex, value: column } }

    (first_columns + week_columns + last_column).each do |hash|
      unless hash[:value].match(hash[:regex])
        raise InvalidStructureException, "Expected '#{hash[:value]}' to match '#{hash[:regex]}'"
      end
    end

    validate_week_dates(week_columns.map { |hash| hash[:value].sub("Week commencing ", "") })

    true
  end

  def self.validate_week_dates(week_dates)
    date_this_week = week_dates.shift(1).first
    week_dates.each do |date_next_week|
      expected_next_date = (Date.parse(date_this_week) + 7).strftime("%d/%m/%Y")
      unless date_next_week == expected_next_date
        raise InvalidStructureException, "Expected 'Week commencing #{date_next_week}' to be 'Week commencing #{expected_next_date}'"
      end
      date_this_week = date_next_week
    end
  end
end
