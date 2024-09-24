require "yaml"
require_relative "../lib/data_processor"
require_relative "../lib/google_sheet"
require_relative "../lib/pagerduty_client"
require_relative "../lib/person"
require_relative "../lib/roles"

ROTA_SHEET_ID = ENV.fetch("ROTA_SHEET_URL").match(/spreadsheets\/d\/([^\/]+)/)[1]
ROTA_TAB_NAME = ENV.fetch("ROTA_TAB_NAME")
TMP_ROTA_CSV = "#{File.dirname(__FILE__)}/../data/tmp_rota.csv".freeze
TMP_ROTA_YML = "#{File.dirname(__FILE__)}/../data/tmp_rota.yml".freeze

roles_config = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

puts "Fetching rota..."
GoogleSheet.new.fetch(sheet_id: ROTA_SHEET_ID, range: "#{ROTA_TAB_NAME}!A1:Z", filepath: TMP_ROTA_CSV)
puts "...downloaded to #{TMP_ROTA_CSV}."

puts "Converting to YML..."
DataProcessor.parse_csv(rota_csv: TMP_ROTA_CSV, roles_config:, rota_yml_output: TMP_ROTA_YML)
puts "...saved to #{TMP_ROTA_YML}."

rota = YAML.load_file(TMP_ROTA_YML, symbolize_names: true)
overridden_names = YAML.load_file("#{File.dirname(__FILE__)}/../config/pagerduty_config_overrides.yml", symbolize_names: true)
pd = PagerdutyClient.new(api_token: ENV.fetch("PAGER_DUTY_API_KEY"))

bulk_yes = true

puts "Fetching list of users from PagerDuty..."
users = pd.users
puts "...fetched."

people = rota[:people].map do |person_data|
  person = Person.new(
    email: person_data[:email],
    team: "Unknown",
    can_do_roles: [], # unknown - but doesn't matter
    assigned_shifts: person_data[:assigned_shifts],
  )
  if (overridden_name = overridden_names[:names].find { |name| name[:derived_from_email] == person.name })
    person.name = overridden_name[:pagerduty]
  end

  if (pagerduty_user = users.find { |user| user["name"] == person.name })
    person.pagerduty_user_id = pagerduty_user["id"]
    person
  else
    puts "No PagerDuty user found for '#{person.name}' (do they have Production Admin access?). Skipping overriding their shifts..."
    nil
  end
end
people.compact!

Roles.new.pagerduty_roles.each do |role_id, role_config|
  puts "Processing #{role_id} shifts..."

  schedule_id = role_config[:pagerduty][:schedule_id]
  shifts_to_assign = people.map do |person|
    person.formatted_shifts(role_id).map { |shift| { person:, **shift } }
  end
  assigned_shifts_this_schedule = pd.assigned_shifts_this_schedule(schedule_id, rota[:dates].first, rota[:dates].last)
  shifts_to_overwrite = pd.shifts_assigned_to_wrong_person(shifts_to_assign, assigned_shifts_this_schedule)

  puts "Overriding #{shifts_to_overwrite.count} individual shifts in PagerDuty..."
  shifts_to_overwrite.each do |shift_to_assign|
    pagerduty_shifts_to_override = pd.shifts_within_timespan(
      shift_to_assign[:start_datetime],
      shift_to_assign[:end_datetime],
      assigned_shifts_this_schedule,
    )

    if pagerduty_shifts_to_override.empty?
      # TODO: this message can happen when someone has two distinct back-to-back
      # shifts, e.g. someone covering bank holiday may have inhours_primary 9:30-17:30
      # followed by oncall_primary 17:30-9:30. PagerDuty API returns this as one
      # 9:30-9:30 shift, which doesn't match our internal representation of two shifts,
      # so we're getting this message. Would be great to fix this in future.
      puts "Warning: failed to assign #{shift_to_assign[:person].name} to the #{role_id} role from #{shift_to_assign[:start_datetime]} to #{shift_to_assign[:end_datetime]}. You'll need to apply this manually in the PagerDuty UI."
      next
    elsif pagerduty_shifts_to_override.count.positive?
      puts "Overriding #{pagerduty_shifts_to_override.count} PagerDuty shifts for this shift."
    end

    pagerduty_shifts_to_override.each do |existing|
      # Sometimes, for whatever reason, part of a long shift has already been assigned to the right user.
      # e.g. a 17:30 Friday -> 09:30 Monday, where perhaps the correct person is assigned apart from for
      # the 09:30 Sunday -> 09:30 Monday slot. In this case, the start/end times for the person's shift
      # don't match and so all of the composite parts of the shift are included in
      # `pagerduty_shifts_to_override`. We can safely skip over the correctly assigned shifts and just
      # let the one 'bad' shift get prompted and overwritten. On subsequent runs of the script, the
      # entire shift would no longer be included in `pagerduty_shifts_to_override`, as the start/end
      # timestamps would now match.
      next if shift_to_assign[:person].name == existing["user"]["summary"]

      puts "Set #{shift_to_assign[:person].name} as the #{role_id} from #{shift_to_assign[:start_datetime]}-#{shift_to_assign[:end_datetime]} (replacing #{existing['user']['summary']})? y/n/exit"

      valid_action = false
      action = false
      if bulk_yes
        action = "y"
      else
        until valid_action
          action = gets.chomp
          valid_action = %w[y n exit].include?(action)
          puts "Option #{action.inspect} not recognised" unless valid_action
        end
      end

      case action
      when "y"
        puts "Overwriting... #{shift_to_assign[:person].pagerduty_user_id} to #{existing['start']} to #{existing['end']}"
        response = pd.create_override(schedule_id, shift_to_assign[:person].pagerduty_user_id, existing["start"], existing["end"])

        if response.code == 400
          puts "...error applying override."
          puts response.body
        else
          puts "...overwrite applied!"
        end
      when "n"
        puts "Skipping."
        next
      when "exit"
        exit
      end
    end
  end
  puts "Finished overriding #{role_id} shifts."
end
