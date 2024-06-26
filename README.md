# govuk-rota-generator

Generates a balanced rota, taking into account:

1. Each developer's availability and eligibility for different cover types.
1. Team burden (it avoids allocating multiple devs from the same team on one shift).
1. Different working patterns (e.g. devs who don't work Fridays will automatically have cover assigned for that day).
1. Partial availability (e.g. a developer may say they're unavailable to do on-call at the weekend, but they would still be available to do in-hours shifts - the generator will make use of that).
1. Bank holiday support - it uses the [GOV.UK bank holiday API](https://www.gov.uk/bank-holidays.json) to detect bank holidays and ensure that the assigned on-call person that week is given the 'in-hours' shift in PagerDuty.

## Setup

In GCP, there's a [govuk-rota-generator 'project'](https://console.cloud.google.com/?project=govuk-rota-generator) which has a google-sheet-fetcher 'service account' (which automatically has its own email address `google-sheet-fetcher@govuk-rota-generator.iam.gserviceaccount.com`).

The 2nd-line-support Google group is an 'Owner' of the service account, so anyone in that group should be able to create a service account key for local use. From the [google-sheet-fetcher service account page](https://console.cloud.google.com/iam-admin/serviceaccounts/details/111167577478691063624;edit=true/keys?orgonly=true&project=govuk-rota-generator&supportedpurview=organizationId):

1. "Add Key" -> "JSON" -> "Create"
2. This will download a JSON file.
3. Store it as `google_service_account_key.json` (which is git-ignored) at the root of this repo.

## Usage

### Create a developer availability form

1. Clone the [form template](https://docs.google.com/forms/d/1PvCMjzCZeELjflHY22p6FH5rtPp3Lvql7LmHGoUSFjM/edit)
2. Update the dates etc, but otherwise make no changes to the form structure
3. Link it to a spreadsheet
4. Share the spreadsheet with `google-sheet-fetcher@govuk-rota-generator.iam.gserviceaccount.com`, as an Editor. (Dismiss the warning about sharing with external email addresses)
5. Add a worksheet / 'tab' called "Auto-generated draft rota" (which is where the draft rota will be pushed by govuk-rota-generator)
6. Send out the form, gather responses

### Get the data ready

Run the `fetch_data` script, passing the URL of your responses spreadsheet as a parameter, e.g.

`ruby bin/fetch_data.rb https://docs.google.com/spreadsheets/d/abc123def456hij789/edit`

This will generate a `data/rota_inputs.yml` file, combining your responses spreadsheet with the [Technical Support Google Sheet](https://docs.google.com/spreadsheets/d/1OTVm_k6MDdCFN1EFzrKXWu4iIPI7uR9mssI8AMwn7lU/edit#gid=1249170615).

The generated file will look something like:

```yml
---
dates:
- 01/04/2024
- 02/04/2024
- 03/04/2024
- 04/04/2024
- 05/04/2024
- 06/04/2024
- 07/04/2024
people:
- email: dev.eloper@digital.cabinet-office.gov.uk
  team: Unknown
  non_working_days: []
  can_do_roles:
  - :inhours_primary
  - :inhours_secondary
  - :inhours_primary_standby
  - :inhours_secondary_standby
  - :oncall_primary
  - :oncall_secondary
  forbidden_in_hours_days: []
  forbidden_on_call_days: []
  assigned_shifts: []
```

### Generate the rota

Run `ruby bin/generate_rota.rb https://docs.google.com/spreadsheets/d/abc123def456hij789/edit`.

This generates a `data/generated_rota.yml` file, which has the same structure as the `data/rota_inputs.yml` file.
But the script will also output a user-friendly CSV to the "Auto-generated draft rota" worksheet you set up earlier, or to STDOUT if you don't provide the Google Sheet CLI parameter. The worksheet/CSV can be used as the `data/rota.csv` in [pay-pagerduty](https://github.com/alphagov/pay-pagerduty) (automating the overriding of PagerDuty schedules).

Note that you can tweak the weighting of each 'role' (e.g. `oncall_primary`) by editing the values in [config/roles.yml](config/roles.yml), to influence how often folks are assigned to particular roles.

### Check the fairness of the rota

Run `ruby bin/calculate_fairness.rb https://docs.google.com/spreadsheets/d/abc123def456hij789/edit`.

This summarises the fairness of the rota. It looks for a "Manually tweaked rota" worksheet, so you'll first need to copy the "Auto-generated draft rota" into a new "Manually tweaked rota" worksheet in the same spreadsheet, and copy over the data. This allows you to freely tweak the output of the rota, without worrying about losing all of your changes next time you run the rota generator.

### Synchronise the rota with PagerDuty

#### Export an API key

You'll need a PagerDuty API key associated with PagerDuty account that has "Global Admin" access (which can be [configured in govuk-user-reviewer](https://github.com/alphagov/govuk-user-reviewer/blob/89102b7778cdf391e4aa6f3e830615093101cc39/config/govuk_tech.yml#L258-L260)):

1. Log into PagerDuty
1. Navigate to "My Profile"
1. Click on "User Settings"
1. Click "Create API User Token"

Export this token as an ENV variable:

```sh
export PAGER_DUTY_API_KEY=$(more ~/pagerduty_token.txt)
```

#### Run the synchroniser script

You can now synchronise a rota with PagerDuty using:

```sh
ruby bin/sync_pagerduty.rb
```

This will:

1. Use the rota in `data/tmp_rota.yml` (created automatically by the "calculate fairness" script)
1. Map the roles in that rota to the roles in `config/roles.yml`, where it finds the corresponding PagerDuty schedule IDs
1. Fetch the list of PagerDuty users and match these up with the users in your rota, warning on any names that are missing from PagerDuty (and skipping over those shifts)±
1. Find conflicts between the PagerDuty schedule and the local rota, and apply overrides to fix them

± These engineers either don't have PagerDuty accounts yet (because they lack Production Admin access - you can [provide temporary access via govuk-user-reviewer](https://github.com/alphagov/govuk-user-reviewer/pull/1194)), or the name derived from their email address doesn't match the name PagerDuty has for them. For the latter, you can specify the mapping of the names in `config/pagerduty_config_overrides.yml`.

By default, the script will ask you to approve each override: `y` to override, `n` to skip, and `exit` to close the script altogether. This means you can do a 'dry run' of the synchroniser by choosing `n` each time.

If you wish to approve all of the overrides at once, you can pass the `--bulk` option:

```sh
ruby bin/sync_pagerduty.rb --bulk
```
