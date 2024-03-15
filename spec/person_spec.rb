require "person"

RSpec.describe Person do
  let(:person) { described_class.new(**person_configuration) }
  let(:person_configuration) do
    {
      email: "developer@digital.cabinet-office.gov.uk",
      team: "Platform Reliability",
      non_working_days: %w[Friday],
      can_do_roles: %i[
        inhours_primary
        inhours_secondary
        inhours_standby_primary
        inhours_standby_secondary
        oncall_primary
      ],
      forbidden_in_hours_days: [
        "01/04/2024", # Monday
        "02/04/2024",
        "03/04/2024",
        "04/04/2024",
        "05/04/2024", # ...to Friday
      ],
      forbidden_on_call_days: [
        "01/04/2024", # Monday
        "02/04/2024",
        "03/04/2024",
        "04/04/2024",
        "05/04/2024", # ...to Friday
        "06/04/2024", # Saturday
        "07/04/2024", # Sunday
      ],
    }
  end

  describe "#email" do
    it "returns the person's email" do
      expect(person.email).to eq("developer@digital.cabinet-office.gov.uk")
    end
  end

  describe "#name" do
    it "derives the name from the person's email" do
      person_configuration[:email] = "norbert.o'hara@digital.cabinet-office.gov.uk"
      expect(person.name).to eq("Norbert O'hara")
    end
  end

  describe "#team" do
    it "returns the person's team" do
      expect(person.team).to eq("Platform Reliability")
    end
  end

  describe "#non_working_days" do
    it "returns array of non-working days" do
      expect(person.non_working_days).to eq(%w[Friday])
    end

    it "returns empty array if unspecified" do
      person_configuration.delete(:non_working_days)
      expect(person.non_working_days).to eq([])
    end
  end

  describe "#can_do_role?" do
    it "returns `true` for roles that the person can do" do
      expect(person.can_do_role?(:inhours_primary)).to eq(true)
      expect(person.can_do_role?(:inhours_standby_secondary)).to eq(true)
    end

    it "returns `false` for roles that the person cannot do" do
      expect(person.can_do_role?(:oncall_secondary)).to eq(false)
    end
  end

  describe "#availability" do
    it "returns a list of roles the person can do on the given date" do
      expect(person.availability(date: "08/04/2024")).to eq(%i[
        inhours_primary
        inhours_secondary
        inhours_standby_primary
        inhours_standby_secondary
        oncall_primary
      ])
    end

    it "returns an empty array if both in-hours and on-call are 'forbidden'" do
      expect(person.availability(date: "01/04/2024")).to eq([])
    end

    it "marks non-working days as unavailable for in-hours" do
      an_otherwise_available_friday = "12/04/2024" # non-working day, but not explicitly a 'forbidden in hours or on-call'
      expect(person.availability(date: an_otherwise_available_friday)).to eq(%i[
        oncall_primary
      ])
    end

    it "marks as unavailable any days already allocated to a shift" do
      person.assign(role: :inhours_primary, date: "08/04/2024")
      expect(person.availability(date: "08/04/2024")).to eq([])
    end
  end

  describe "#assign" do
    it "allows assigning a supported role on an available date" do
      expect { person.assign(role: :inhours_primary, date: "08/04/2024") }.not_to raise_exception
    end

    it "raises an error when assigning a supported in-hours role on a forbidden date" do
      expect { person.assign(role: :inhours_primary, date: "01/04/2024") }.to raise_exception(ForbiddenDateException)
    end

    it "raises an error when assigning a supported on-call role on an available date" do
      expect { person.assign(role: :oncall_primary, date: "07/04/2024") }.to raise_exception(ForbiddenDateException)
    end

    it "raises an error when assigning an unsupported role on an available date" do
      expect { person.assign(role: :oncall_secondary, date: "08/04/2024") }.to raise_exception(ForbiddenRoleException)
    end

    it "raises an error when assigning multiple supported roles on an available date" do
      expect { person.assign(role: :inhours_primary, date: "08/04/2024") }.not_to raise_exception
      expect { person.assign(role: :inhours_secondary, date: "08/04/2024") }.to raise_exception(MultipleRolesException)
    end
  end

  describe "#unassign" do
    it "allows unassigning an existing assigned shift" do
      person.assign(role: :inhours_primary, date: "08/04/2024")
      expect { person.unassign(role: :inhours_primary, date: "08/04/2024") }.not_to raise_exception
    end

    it "raises an error when unassigning a shift that has already been unassigned" do
      person.assign(role: :inhours_primary, date: "08/04/2024")
      expect { person.unassign(role: :inhours_primary, date: "08/04/2024") }.not_to raise_exception
      expect { person.unassign(role: :inhours_primary, date: "08/04/2024") }.to raise_exception(ShiftNotAssignedException)
    end
  end

  describe "#assigned_shifts" do
    it "returns an empty array if no shifts assigned" do
      expect(person.assigned_shifts).to eq([])
    end

    it "returns an array of all shifts that have been assigned, in date order" do
      person.assign(role: :inhours_primary, date: "09/04/2024")
      person.assign(role: :inhours_primary, date: "08/04/2024")
      expect(person.assigned_shifts).to eq([
        {
          date: "08/04/2024",
          role: :inhours_primary,
        },
        {
          date: "09/04/2024",
          role: :inhours_primary,
        },
      ])
    end

    it "returns an array of all shifts that have been assigned and doesn't include any unassigned ones" do
      person.assign(role: :inhours_primary, date: "08/04/2024")
      person.assign(role: :inhours_primary, date: "09/04/2024")
      person.assign(role: :inhours_primary, date: "10/04/2024")
      person.unassign(role: :inhours_primary, date: "09/04/2024")
      expect(person.assigned_shifts).to eq([
        {
          date: "08/04/2024",
          role: :inhours_primary,
        },
        {
          date: "10/04/2024",
          role: :inhours_primary,
        },
      ])
    end
  end

  describe "#formatted_shifts" do
    it "takes an optional argument to specify the shift type" do
      person.assign(role: :inhours_primary, date: "08/04/2024")
      person.assign(role: :oncall_primary, date: "09/04/2024")

      expect(person.formatted_shifts(:oncall_primary)).to eq([
        {
          role: :oncall_primary,
          start_datetime: "2024-04-09T17:30:00+01:00",
          end_datetime: "2024-04-10T09:30:00+01:00",
        },
      ])
    end

    it "merges shifts when there is no gap between them" do
      person.assign(role: :oncall_primary, date: "12/04/2024") # Friday
      person.assign(role: :oncall_primary, date: "13/04/2024") # Saturday
      person.assign(role: :oncall_primary, date: "14/04/2024") # Saturday
      expect(person.formatted_shifts).to eq([
        {
          role: :oncall_primary,
          start_datetime: "2024-04-12T17:30:00+01:00",
          end_datetime: "2024-04-15T09:30:00+01:00",
        },
      ])
    end
  end

  describe "#to_h" do
    it "returns all the metadata about the person needed to generate a rota" do
      expected_hash = person_configuration
      expected_hash[:non_working_days] = %w[Friday]
      expected_hash[:assigned_shifts] = []
      expect(person.to_h.transform_keys(&:to_sym)).to eq(expected_hash)
    end
  end
end
