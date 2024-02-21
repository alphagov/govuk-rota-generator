require "person"

RSpec.describe Person do
  let(:person) do
    described_class.new(
      name: "Dev Eloper",
      team: "Platform Reliability",
      can_do_roles: %i[
        inhours_primary
        inhours_secondary
        inhours_primary_standby
        inhours_secondary_standby
        oncall_primary
      ],
      forbidden_weeks: [3, 7],
    )
  end

  describe "#name" do
    it "returns the person's name" do
      expect(person.name).to eq("Dev Eloper")
    end
  end

  describe "#team" do
    it "returns the person's team" do
      expect(person.team).to eq("Platform Reliability")
    end
  end

  describe "#can_do_role?" do
    it "returns `true` for roles that the person can do" do
      expect(person.can_do_role?(:inhours_primary)).to eq(true)
      expect(person.can_do_role?(:inhours_secondary_standby)).to eq(true)
    end

    it "returns `false` for roles that the person cannot do" do
      expect(person.can_do_role?(:oncall_secondary)).to eq(false)
    end
  end

  describe "#availability" do
    it "returns a list of roles the person can do in the given week" do
      expect(person.availability(week: 1)).to eq(%i[
        inhours_primary
        inhours_secondary
        inhours_primary_standby
        inhours_secondary_standby
        oncall_primary
      ])
    end

    it "returns an empty array if the week is a 'forbidden' one" do
      expect(person.availability(week: 3)).to eq([])
    end
  end

  describe "#assign" do
    it "allows assigning a supported role in an available week" do
      expect { person.assign(role: :inhours_primary, week: 1) }.not_to raise_exception
    end

    it "raises an error when assigning a supported role in a forbidden week" do
      expect { person.assign(role: :inhours_primary, week: 3) }.to raise_exception(ForbiddenWeekException)
    end

    it "raises an error when assigning an unsupported role in an available week" do
      expect { person.assign(role: :oncall_secondary, week: 3) }.to raise_exception(ForbiddenRoleException)
    end

    it "raises an error when assigning multiple supported roles in an available week" do
      expect { person.assign(role: :inhours_primary, week: 1) }.not_to raise_exception
      expect { person.assign(role: :inhours_secondary, week: 1) }.to raise_exception(MultipleRolesException)
    end
  end

  describe "#unassign" do
    it "allows unassigning an existing assigned shift" do
      person.assign(role: :inhours_primary, week: 1)
      expect { person.unassign(role: :inhours_primary, week: 1) }.not_to raise_exception
    end

    it "raises an error when unassigning a shift that has already been unassigned" do
      person.assign(role: :inhours_primary, week: 1)
      expect { person.unassign(role: :inhours_primary, week: 1) }.not_to raise_exception
      expect { person.unassign(role: :inhours_primary, week: 1) }.to raise_exception(ShiftNotAssignedException)
    end
  end

  describe "#assigned_shifts" do
    it "returns an empty array if no shifts assigned" do
      expect(person.assigned_shifts).to eq([])
    end

    it "returns an array of all shifts that have been assigned" do
      person.assign(role: :inhours_primary, week: 1)
      person.assign(role: :inhours_secondary, week: 2)
      expect(person.assigned_shifts).to eq([
        {
          week: 1,
          role: :inhours_primary,
        },
        {
          week: 2,
          role: :inhours_secondary,
        },
      ])
    end

    it "returns an array of all shifts that have been assigned and doesn't include any unassigned ones" do
      person.assign(role: :inhours_primary, week: 1)
      person.assign(role: :inhours_secondary, week: 2)
      person.assign(role: :oncall_primary, week: 4)
      person.unassign(role: :inhours_secondary, week: 2)
      expect(person.assigned_shifts).to eq([
        {
          week: 1,
          role: :inhours_primary,
        },
        {
          week: 4,
          role: :oncall_primary,
        },
      ])
    end
  end
end
