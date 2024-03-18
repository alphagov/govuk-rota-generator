require "date"
require_relative "./roles"

class ForbiddenRoleException < StandardError; end
class ForbiddenDateException < StandardError; end
class MultipleRolesException < StandardError; end
class ShiftNotAssignedException < StandardError; end

class Person
  attr_accessor :pagerduty_user_id
  attr_reader :email, :team, :can_do_roles, :non_working_days, :assigned_shifts

  def initialize(email:, team:, can_do_roles:, forbidden_in_hours_days: [], forbidden_on_call_days: [], non_working_days: [], assigned_shifts: [])
    @email = email
    @team = team
    @non_working_days = non_working_days
    @can_do_roles = can_do_roles
    @forbidden_in_hours_days = forbidden_in_hours_days
    @forbidden_on_call_days = forbidden_on_call_days
    @assigned_shifts = assigned_shifts
    @roles_config = Roles.new
  end

  def name
    email.match(/(.+)@(.+)$/)[1].split(".").map(&:capitalize).join(" ")
  end

  def can_do_role?(role)
    @can_do_roles.include?(role)
  end

  def availability(date:)
    return [] if @assigned_shifts.find { |shift| shift[:date] == date }

    available_roles = @can_do_roles
    day_of_week = Date.parse(date).strftime("%A")

    if @forbidden_in_hours_days.include?(date) || non_working_days.include?(day_of_week)
      available_roles -= @roles_config.by_type(%i[weekdays])
    end

    if @forbidden_on_call_days.include?(date)
      available_roles -= @roles_config.by_type(%i[weekends weeknights])
    end

    available_roles
  end

  def assign(role:, date:)
    if (conflicting_shift = @assigned_shifts.find { |shift| shift[:date] == date })
      raise MultipleRolesException, "Failed to assign role #{role} to #{email} on date #{date} as they're already assigned to #{conflicting_shift[:role]}"
    end

    raise ForbiddenRoleException unless can_do_role?(role)
    raise ForbiddenDateException unless availability(date:).include?(role)

    @assigned_shifts << { date:, role: }

    @assigned_shifts.sort! { |a, b| Date.parse(a[:date]) <=> Date.parse(b[:date]) }
  end

  def unassign(role:, date:)
    shift_to_unassign = @assigned_shifts.find { |shift| shift[:date] == date && shift[:role] == role }
    raise ShiftNotAssignedException if shift_to_unassign.nil?

    @assigned_shifts.delete(shift_to_unassign)
  end

  def formatted_shifts(shift_type = nil)
    shifts_to_format = shift_type.nil? ? @assigned_shifts : @assigned_shifts.select { |shift| shift[:role] == shift_type }
    shifts_to_assign = shifts_to_format.map do |shift|
      {
        role: shift[:role],
        start_datetime: @roles_config.start_datetime(shift[:date], shift[:role]),
        end_datetime: @roles_config.end_datetime(shift[:date], shift[:role]),
      }
    end
    consolidate_shifts(shifts_to_assign)
  end

  def to_h
    excluded_ivars = ["@roles_config"]

    hash = {}
    instance_variables.each do |variable|
      next if excluded_ivars.include? variable.to_s

      value = instance_variable_get(variable)
      if value.is_a?(Array) && value.first.is_a?(Hash)
        value = value.map { |element| element.transform_keys(&:to_s) }
      end

      hash[variable.to_s.delete("@")] = value
    end
    hash
  end

private

  def consolidate_shifts(shifts_to_assign)
    # Consolidate shifts if there is no gap between them,
    # e.g. one Friday 17:30-9:30 shift followed by one Saturday 9:30 - Sunday 9:30 shift
    # would become a single Friday 17:30 - Sunday 9:30 shift
    index = shifts_to_assign.count - 1
    while index.positive?
      shift = shifts_to_assign[index]
      earlier_shift = shifts_to_assign[index - 1]

      if earlier_shift[:end_datetime] == shift[:start_datetime] &&
          earlier_shift[:person] == shift[:person]
        consolidated_shift = shift.dup
        consolidated_shift[:start_datetime] = earlier_shift[:start_datetime]
        shifts_to_assign.delete(shift)
        shifts_to_assign.delete(earlier_shift)
        shifts_to_assign << consolidated_shift
        shifts_to_assign.sort_by! { |hash| Date.parse(hash[:start_datetime]) }
        index = shifts_to_assign.count - 1 # go back to beginning of queue in case there are more to merge into this shift
      else
        index -= 1
      end
    end
    shifts_to_assign
  end
end
