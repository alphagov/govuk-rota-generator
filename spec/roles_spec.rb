require "roles"

RSpec.describe Roles do
  describe ".initialize" do
    it "defaults to the roles config at data/roles.yml" do
      expect(YAML).to receive(:load_file).with(
        "#{File.dirname(__FILE__).sub('spec', 'lib')}/../config/roles.yml",
        symbolize_names: true,
      )

      described_class.new
    end
  end

  describe "#config" do
    it "returns the config hash" do
      roles_config = {
        foo: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
      }
      roles = described_class.new(config: roles_config)
      expect(roles.config).to eq(roles_config)
    end
  end

  describe "#type" do
    it "returns array of all role types" do
      roles_config = {
        foo: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        bar: {
          value: 1,
          weekdays: false,
          weeknights: false,
          weekends: true,
        },
      }
      roles = described_class.new(config: roles_config)
      expect(roles.types).to eq(%i[foo bar])
    end
  end

  describe "#by_type" do
    it "returns all roles that match at least one of the supplied filters" do
      roles_config = {
        foo: {
          value: 1,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        bar: {
          value: 1,
          weekdays: false,
          weeknights: true,
          weekends: false,
        },
      }
      roles = described_class.new(config: roles_config)
      expect(roles.by_type(%i[weekdays])).to eq([:foo])
      expect(roles.by_type(%i[weekdays weeknights])).to eq(%i[foo bar])
    end
  end

  describe "#value_of_shifts" do
    it "returns summed value of all assigned shifts" do
      roles_config = {
        foo: {
          value: 2,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
      }
      shifts = [
        { role: :foo, date: "01/04/2024" },
        { role: :foo, date: "02/04/2024" },
      ]
      roles = described_class.new(config: roles_config)
      expect(roles.value_of_shifts(shifts)).to eq(4)
    end
  end

  describe "#pagerduty_roles" do
    it "returns all the role IDs of roles that should correspond to a specific schedule in Pagerduty" do
      pagerduty_role = {
        value: 2,
        weekdays: true,
        weeknights: false,
        weekends: false,
        pagerduty: {
          schedule_name: "GOV.UK Secondary (2nd Call)",
          schedule_id: "P752O37",
        },
      }
      roles_config = {
        foo: {
          value: 2,
          weekdays: true,
          weeknights: false,
          weekends: false,
        },
        bar: pagerduty_role,
      }
      roles = described_class.new(config: roles_config)
      expect(roles.pagerduty_roles).to eq({ bar: pagerduty_role })
    end
  end
end
