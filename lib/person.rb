class ForbiddenRoleException < StandardError; end
class ForbiddenWeekException < StandardError; end
class MultipleRolesException < StandardError; end
class ShiftNotAssignedException < StandardError; end

class Person
  attr_reader :name, :team, :assigned_shifts

  def initialize(name:, team:, can_do_roles:, forbidden_weeks:)
    @name = name
    @team = team
    @can_do_roles = can_do_roles
    @forbidden_weeks = forbidden_weeks
    @assigned_shifts = []
  end

  def can_do_role?(role)
    @can_do_roles.include?(role)
  end

  def availability(week:)
    @forbidden_weeks.include?(week) ? [] : @can_do_roles
  end

  def assign(role:, week:)
    raise ForbiddenRoleException.new unless can_do_role?(role)
    raise ForbiddenWeekException.new if availability(week: week).empty?
    if (conflicting_shift = @assigned_shifts.find { |shift| shift[:week] == week })
      raise MultipleRolesException.new("Failed to assign role #{role} to #{name} in week #{week} as they're already assigned to #{conflicting_shift[:role]}")
    end

    @assigned_shifts << { week: week, role: role }
  end

  def unassign(role:, week:)
    shift_to_unassign = @assigned_shifts.find { |shift| shift[:week] == week && shift[:role] == role }
    raise ShiftNotAssignedException if shift_to_unassign.nil?

    @assigned_shifts.delete(shift_to_unassign)
  end

  def weight_of_shifts
    value_mappings = {
      inhours_primary: 1.5,
      inhours_secondary: 1,
      inhours_primary_standby: 0.5,
      inhours_secondary_standby: 0.5,
      inhours_shadow: 0,
      oncall_primary: 2.5,
      oncall_secondary: 2,
    }
    @assigned_shifts.reduce(0) do |sum, shift|
      value_of_shift = value_mappings[shift[:role].to_sym]
      # hack for tests that make reference to `:some_role`
      value_of_shift = value_of_shift.nil? ? 0 : value_of_shift
      sum + value_of_shift
    end
  end
end
