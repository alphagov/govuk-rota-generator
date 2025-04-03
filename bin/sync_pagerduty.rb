require "yaml"
require_relative "../lib/data_processor"
require_relative "../lib/google_sheet"
require_relative "../lib/pagerduty_client"
require_relative "../lib/person"
require_relative "../lib/roles"

ROTA_SHEET_ID = ENV.fetch("ROTA_SHEET_URL").match(/spreadsheets\/d\/([^\/]+)/)[1]
ROTA_TAB_NAME = ENV.fetch("ROTA_TAB_NAME")
PAGER_DUTY_API_KEY = ENV.fetch("PAGER_DUTY_API_KEY")
TMP_ROTA_CSV = "#{File.dirname(__FILE__)}/../data/tmp_rota.csv".freeze
TMP_ROTA_YML = "#{File.dirname(__FILE__)}/../data/tmp_rota.yml".freeze

class SyncPagerduty
  def execute(bulk_apply_overrides: false)
    errors_found = false

    roles_config = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

    puts "Fetching rota..."
    GoogleSheet.new.fetch(sheet_id: ROTA_SHEET_ID, range: "#{ROTA_TAB_NAME}!A1:Z", filepath: TMP_ROTA_CSV)
    puts "...downloaded to #{TMP_ROTA_CSV}."

    puts "Converting to YML..."
    DataProcessor.parse_csv(rota_csv: TMP_ROTA_CSV, roles_config:, rota_yml_output: TMP_ROTA_YML)
    puts "...saved to #{TMP_ROTA_YML}."

    rota = YAML.load_file(TMP_ROTA_YML, symbolize_names: true)
    overridden_names = YAML.load_file("#{File.dirname(__FILE__)}/../config/pagerduty_config_overrides.yml", symbolize_names: true)
    pd = PagerdutyClient.new(api_token: PAGER_DUTY_API_KEY)

    if bulk_apply_overrides
      puts "Bulk-applying overrides..."
    end

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

      last_shift = person.assigned_shifts.map { |shift| Time.zone.parse(shift[:date]) }.max

      if last_shift < Time.zone.now
        puts "Skipping processing overrides for #{person.name} as their last shift was on #{last_shift}."
        nil
      elsif (pagerduty_user = users.find { |user| user["name"] == person.name })
        person.pagerduty_user_id = pagerduty_user["id"]
        person
      else
        puts "No PagerDuty user found for '#{person.name}' (do they have Production Admin access?). Skipping overriding their shifts..."
        errors_found = true
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
      shifts_to_overwrite = shifts_to_overwrite.reject do |shift|
        pd.in_past?(shift[:end_datetime])
      end

      puts "Overriding #{shifts_to_overwrite.count} shifts in PagerDuty..."
      shifts_to_overwrite.each do |shift_to_assign|
        existing_shifts = pd.find_corresponding_shifts(assigned_shifts_this_schedule, shift_to_assign)
        existing_users = existing_shifts.map { |shift| shift["user"]["summary"] }

        puts "Set #{shift_to_assign[:person].name} as the #{role_id} from #{shift_to_assign[:start_datetime]}-#{shift_to_assign[:end_datetime]} (replacing #{existing_users.join(' and ')})? y/n/exit"

        valid_action = false
        action = false
        if bulk_apply_overrides
          action = "y"
        else
          until valid_action
            action = $stdin.gets.chomp
            valid_action = %w[y n exit].include?(action)
            puts "Option #{action.inspect} not recognised" unless valid_action
          end
        end

        case action
        when "y"
          puts "Overwriting... #{shift_to_assign[:person].pagerduty_user_id} to #{shift_to_assign[:start_datetime]} to #{shift_to_assign[:end_datetime]}"
          response = pd.create_override(schedule_id, shift_to_assign[:person].pagerduty_user_id, shift_to_assign[:start_datetime], shift_to_assign[:end_datetime])

          if response.code == 400
            puts "...error applying override."
            puts response.body
            errors_found = true
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
      puts "Finished overriding #{role_id} shifts."
    end

    if errors_found
      puts "PagerDuty wasn't able to fully synchronise. See output above."
      exit 1
    end
  end
end
