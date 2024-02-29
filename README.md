# govuk-rota-generator

Generates a balanced rota, taking into account each developer's availability and eligibility for different cover types.

There are some limitations to the generator, which we hope to resolve in future iterations:

1. Currently no way of capping certain shift types.
1. It doesn't account for different working patterns (e.g. devs who don't work Fridays currently have to find cover)
1. The week is marked as 'unavailable' even if only one cover type is off limits. For example, a developer may say they're unavailable to do on-call at the weekend, but they would still be available to do in-hours shifts.
1. It doesn't account for bank holidays.
1. It doesn't account for team burden (i.e. there's nothing preventing it allocating multiple devs from the same team on one shift).
1. It doesn't give a perfectly balanced rota (some devs will be allocated more slots than others), but a 'balancing' step after a first pass could be something we look at in future.

We hope one day to make the rota generator think in terms of days rather than weeks, and also have tighter integration with the `pay-pagerduty` repo (e.g. merging together under a new name).

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
3. Send out the form, gather responses
4. Link it to a spreadsheet
5. Share the spreadsheet with `google-sheet-fetcher@govuk-rota-generator.iam.gserviceaccount.com`, as a Viewer. (Dismiss the warning about sharing with external email addresses)

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

Run `ruby bin/generate_rota.rb` (it will output to STDOUT).

You can tweak the weighting of each 'role' (e.g. `oncall_primary`) by editing the values in [config/roles.yml](config/roles.yml).

The generated output can be used as the `data/rota.csv` in [pay-pagerduty](https://github.com/alphagov/pay-pagerduty), which automates the overriding of PagerDuty schedules.
