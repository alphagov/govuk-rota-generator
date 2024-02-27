require "date"
require_relative "./randomiser"

class ForbiddenRoleException < StandardError; end
class ForbiddenDateException < StandardError; end
class MultipleRolesException < StandardError; end
class ShiftNotAssignedException < StandardError; end

class Person
  attr_reader :email, :team, :non_working_days, :assigned_shifts, :random_factor

  def initialize(email:, team:, can_do_roles:, forbidden_in_hours_days:, forbidden_on_call_days:, non_working_days: [])
    @email = email
    @team = team
    @non_working_days = non_working_days
    @can_do_roles = can_do_roles
    @forbidden_in_hours_days = forbidden_in_hours_days
    @forbidden_on_call_days = forbidden_on_call_days
    @assigned_shifts = []
    @random_factor = Randomiser.instance.next_float
  end

  def name
    email.match(/(.+)@(.+)$/)[1].split(".").map(&:capitalize).join(" ")
  end

  def can_do_role?(role)
    @can_do_roles.include?(role)
  end

  def availability(date:)
    available_roles = @can_do_roles
    day_of_week = Date.parse(date).strftime("%A")

    if @forbidden_in_hours_days.include?(date) || non_working_days.include?(day_of_week)
      available_roles -= %i[
        inhours_primary
        inhours_secondary
        inhours_primary_standby
        inhours_secondary_standby
      ]
    end

    if @forbidden_on_call_days.include?(date)
      available_roles -= %i[
        oncall_primary
        oncall_secondary
      ]
    end

    available_roles
  end

  def assign(role:, date:)
    raise ForbiddenRoleException unless can_do_role?(role)
    raise ForbiddenDateException if availability(date:).empty?

    if (conflicting_shift = @assigned_shifts.find { |shift| shift[:date] == date })
      raise MultipleRolesException, "Failed to assign role #{role} to #{email} on date #{date} as they're already assigned to #{conflicting_shift[:role]}"
    end

    @assigned_shifts << { date:, role: }
  end

  def unassign(role:, date:)
    shift_to_unassign = @assigned_shifts.find { |shift| shift[:date] == date && shift[:role] == role }
    raise ShiftNotAssignedException if shift_to_unassign.nil?

    @assigned_shifts.delete(shift_to_unassign)
  end

  def to_h
    excluded_ivars = ["@random_factor", "@assigned_shifts"]

    hash = {}
    instance_variables.each do |variable|
      next if excluded_ivars.include? variable.to_s

      value = instance_variable_get(variable)
      hash[variable.to_s.delete("@")] = value
    end
    hash
  end
end
