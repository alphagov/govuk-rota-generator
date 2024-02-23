require "date"
require_relative "./randomiser"

class ForbiddenRoleException < StandardError; end
class ForbiddenWeekException < StandardError; end
class MultipleRolesException < StandardError; end
class ShiftNotAssignedException < StandardError; end

class Person
  attr_reader :email, :team, :non_working_days, :assigned_shifts, :random_factor

  def initialize(email:, team:, can_do_roles:, forbidden_weeks:, non_working_days: [])
    @email = email
    @team = team
    @non_working_days = non_working_days
    @can_do_roles = can_do_roles
    @forbidden_weeks = forbidden_weeks
    @assigned_shifts = []
    @random_factor = Randomiser.instance.next_float
  end

  def name
    email.match(/(.+)@(.+)$/)[1].split(".").map(&:capitalize).join(" ")
  end

  def can_do_role?(role)
    @can_do_roles.include?(role)
  end

  def availability(week:)
    @forbidden_weeks.include?(week) ? [] : @can_do_roles
  end

  def assign(role:, week:)
    raise ForbiddenRoleException unless can_do_role?(role)
    raise ForbiddenWeekException if availability(week:).empty?
    if (conflicting_shift = @assigned_shifts.find { |shift| shift[:week] == week })
      raise MultipleRolesException, "Failed to assign role #{role} to #{email} in week #{week} as they're already assigned to #{conflicting_shift[:role]}"
    end

    @assigned_shifts << { week:, role: }
  end

  def unassign(role:, week:)
    shift_to_unassign = @assigned_shifts.find { |shift| shift[:week] == week && shift[:role] == role }
    raise ShiftNotAssignedException if shift_to_unassign.nil?

    @assigned_shifts.delete(shift_to_unassign)
  end
end
