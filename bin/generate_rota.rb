require "yaml"
require_relative "../lib/person"
require_relative "../lib/rota_generator"
require_relative "../lib/rota_presenter"

yml = YAML.load_file(File.dirname(__FILE__) + "/../data/rota_inputs.yml", symbolize_names: true)
people = yml[:people].map { |person_data| Person.new(**person_data) }
dates = yml[:dates]
roles_config = YAML.load_file("#{File.dirname(__FILE__)}/../config/roles.yml", symbolize_names: true)

generator = RotaGenerator.new(dates:, people:, roles_config:)
generator.fill_slots

rota_output_file = "#{File.dirname(__FILE__)}/../data/generated_rota.yml"
generator.write_rota(filepath: rota_output_file)

presenter = RotaPresenter.new(filepath: rota_output_file)

puts "All shifts allocated. See CSV below:"
puts ""
puts presenter.to_csv
puts ""
