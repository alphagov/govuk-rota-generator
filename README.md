# govuk-rota-generator

Generates a balanced rota, taking into account each developer's availability and eligibility for different cover types.

There are some limitations to the generator, which we hope to resolve in future iterations:

1. Currently no way of capping certain shift types (e.g. maximum two shadow shifts).
1. It doesn't account for different working patterns (e.g. devs who don't work Fridays currently have to find cover)
1. The week is marked as 'unavailable' even if only one cover type is off limits. For example, a developer may say they're unavailable to do on-call at the weekend, but they would still be available to do in-hours shifts.
1. It doesn't account for bank holidays.
1. It doesn't account for team burden (i.e. there's nothing preventing it allocating multiple devs from the same team on one shift).
1. It doesn't give a perfectly balanced rota (some devs will be allocated more slots than others), but a 'balancing' step after a first pass could be something we look at in future.

We hope one day to make the rota generator think in terms of days rather than weeks, and also have tighter integration with the `pay-pagerduty` repo (e.g. merging together under a new name).

## Usage

Once you've generated a `/data/combined.csv` file as per [Creating the input data](#creating-the-input-data), you can generate a rota by running `ruby bin/generate_rota.rb` (it will output to STDOUT).

Tweak the weighting in that file to place more or less emphasis on different cover types (e.g. oncall_primary).

The generated output can be used as the `data/rota.csv` in [pay-pagerduty](https://github.com/alphagov/pay-pagerduty), which automates the overriding of PagerDuty schedules.

## Creating the input data

This was very much hacked together for a prototype, and needs rebuilding properly at some point.

1. Download the [Technical Support Google Sheet](https://docs.google.com/spreadsheets/d/1OTVm_k6MDdCFN1EFzrKXWu4iIPI7uR9mssI8AMwn7lU/edit#gid=1249170615) as a CSV, storing in `data/people.csv`.
   This CSV describes what roles developers are eligible for, e.g. whether or not they can do on-call.
   Remember to delete the second row from the CSV, as this only contains hint text.
2. Export the [Rota Availability Google Forms Responses](https://docs.google.com/forms/d/11Az5Y6acNYiqJPiIigHJRF-KdT8Fnpp2jmoQNysKzmg/edit#responses) to Google Sheets (use the "View in Sheets" option). Rename row F onwards to something that identifies each week (e.g. "Week 1 (03/04/23 - 09/04/23)"). Now export the sheet as a CSV, storing it as `data/responses.csv`. This CSV describes which weeks developers are unavailable.
3. Check your `responses.csv` file should look something like below (also ensure that any newlines have been removed from the output):

```csv
Timestamp,What is your name,What team will you be on? (team),"If you work different hours to the 9.30am-5.30pm 2nd line shifts, please state your hours",Do you have any non working days? [Non working day(s)],Week 1 (03/04/23 - 09/04/23),Week 2 (10/04/23 - 16/04/23),Week 3 (17/04/23 - 23/04/23),Week 4 (24/04/23 - 30/04/23),Week 5 (01/05/23 - 07/05/23),Week 6 (08/05/23 - 14/05/23),Week 7 (15/05/23 - 21/05/23),Week 8 (22/05/23 - 28/05/23),Week 9 (29/05/23 - 04/06/23),Week 10 (05/06/23 - 11/06/23),Week 11 (12/06/23 - 18/06/23),Week 12 (19/06/23 - 25/06/23),Week 13 (26/06/23 - 02/07/23),Need to elaborate on any of the above?
10/02/2023 16:54:04,Some Person,Find and View,,,,,,,,"Not available for in-hours, Not available for on-call weekday nights, Not available for on-call over the weekend",,,,"Not available for in-hours, Not available for on-call weekday nights, Not available for on-call over the weekend",,,,
```

4. Update the `week_headers` variable in `bin/combine_csvs.rb` to refer to the headings you wrote in step 2, so that it knows which columns to read.

5. Run `ruby bin/combine_csvs.rb`. This will generate a `data/combined.csv` file.

The generated file will look something like:

```csv
name,team,can_do_inhours_primary,can_do_inhours_secondary,can_do_inhours_shadow,can_do_inhours_primary_standby,can_do_inhours_secondary_standby,can_do_oncall_primary,can_do_oncall_secondary,forbidden_weeks
Some Person,Find and View,false,false,false,false,false,true,true,"6,10"
```
