require_relative "../lib/pagerduty_client"
require_relative "../lib/person"
require_relative "../lib/roles"

rota = YAML.load_file(File.dirname(__FILE__) + "/../data/tmp_rota.yml", symbolize_names: true)
overridden_names = YAML.load_file(File.dirname(__FILE__) + "/../config/pagerduty_config_overrides.yml", symbolize_names: true)
pd = PagerdutyClient.new(api_token: ENV.fetch("PAGER_DUTY_API_KEY"))

bulk_yes = false
if ARGV.first == "--bulk"
  puts "--bulk parameter supplied. Bulk-applying overrides..."
  bulk_yes = true
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
  shifts_to_assign = people.map do |person|
    person.formatted_shifts(role_id).map { |shift| { person:, **shift } }
  end

  schedule_id = role_config[:pagerduty][:schedule_id]
  assigned_shifts_this_schedule = pd.schedule(schedule_id, rota[:dates].first, rota[:dates].last)

  shifts_to_overwrite = shifts_to_assign.flatten.reject do |shift_to_assign|
    currently_assigned = assigned_shifts_this_schedule.find do |existing_shift|
      existing_shift["start"] == shift_to_assign[:start_datetime]
    end
    currently_assigned && currently_assigned["user"]["summary"] == shift_to_assign[:person].name # person already assigned to this slot
  end

  puts "Overriding #{shifts_to_overwrite.count} individual shifts in PagerDuty..."
  shifts_to_overwrite.each do |shift_to_assign|
    pagerduty_shifts_to_override = assigned_shifts_this_schedule.select do |shift|
      Time.zone.parse(shift["start"]) >= Time.zone.parse(shift_to_assign[:start_datetime]) &&
        Time.zone.parse(shift["end"]) <= Time.zone.parse(shift_to_assign[:end_datetime])
    end

    if pagerduty_shifts_to_override.empty?
      puts "It was not possible to override #{shift_to_assign} for role #{role_id}."
      puts "  This means that a past override has merged multiple distinct shifts (e.g. one unbroken shift from in-hours to on-call)."
      puts "  The rota generator can't currently override 'parts' of an existing shift - it can only override the shift in its entirety."
      puts "  You will therefore need to manually apply this shift in the PagerDuty UI."
      next
    elsif pagerduty_shifts_to_override.count > 1
      puts "Overriding #{pagerduty_shifts_to_override.count} PagerDuty shifts for this shift."
    end

    pagerduty_shifts_to_override.each do |existing|
      puts "Set #{shift_to_assign[:person].name} as the #{role_id} from #{shift_to_assign[:start_datetime]}-#{shift_to_assign[:end_datetime]} (replacing #{existing['user']['summary']})? y/n/exit"

      valid_action = false
      action = false
      if bulk_yes
        action = "y"
      else
        while !valid_action
          action = (gets).chomp
          valid_action = ["y", "n", "exit"].include?(action)
          puts "Option #{action.inspect} not recognised" unless valid_action
        end
      end

      if action == "y"
        puts "Overwriting... #{shift_to_assign[:person].pagerduty_user_id} to #{existing["start"]} to #{existing["end"]}"
        response = pd.create_override(schedule_id, shift_to_assign[:person].pagerduty_user_id, existing["start"], existing["end"])

        if response.code == 400
          puts "...error applying override."
          puts response.body
        else
          puts "...overwrite applied!"
        end
      elsif action == "n"
        puts "Skipping."
        next
      elsif action == "exit"
        exit
      end
    end
  end
  puts "Finished overriding #{role_id} shifts."
end
