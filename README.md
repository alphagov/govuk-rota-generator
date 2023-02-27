# govuk-rota-generator

Work in progress.

Instructions:

- Download [Technical Support Google Sheet](https://docs.google.com/spreadsheets/d/1OTVm_k6MDdCFN1EFzrKXWu4iIPI7uR9mssI8AMwn7lU/edit#gid=1249170615) as CSV, store as `data/people.csv`
- Download [Rota Availability Google Forms Responses](https://docs.google.com/forms/d/11Az5Y6acNYiqJPiIigHJRF-KdT8Fnpp2jmoQNysKzmg/edit#responses) as CSV, store as `data/responses.csv`.
  - You may first want to export to Google Sheets, and then rename the first row columns to "Week 1 (03/04/23 - 09/04/23)", and so on. Then export the CSV from Google Sheets.
- Run `ruby inputs/combine_csvs.rb` and see the generated `data/combined.csv` file

TODO: we will use this combined dataset to generate a rota.
