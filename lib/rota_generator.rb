require "yaml"

class RotaGenerator
  def initialize(dates:, people:, roles_config:)
    @dates = dates
    @people = people
    @roles_config = Roles.new(config: roles_config)
  end

  def fill_slots
    people_queue = @people

    @dates.each do |date|
      day_of_week = Date.parse(date).strftime("%A")

      roles_to_fill = if %w[Saturday Sunday].include?(day_of_week)
                        @roles_config.by_type(%i[weekends])
                      else
                        @roles_config.by_type(%i[weekdays weeknights])
                      end

      roles_to_fill.each do |role|
        # require "byebug"
        # byebug if date == "05/04/2024"
        available_candidates = people_queue.select { |person| person.availability(date:).include?(role) }
        if available_candidates.empty?
          puts "NOBODY ABLE TO FILL #{role} on #{date}"
          break
        end

        person_to_assign = available_candidates.first
        person_to_assign.assign(role:, date:)
        people_queue.sort_by! { |person| @roles_config.value_of_shifts(person.assigned_shifts) }
      end
    end
  end

  def write_rota(filepath:)
    roles = {}
    @roles_config.config.each do |key, value|
      roles[key.to_s] = value.transform_keys(&:to_s)
    end

    output = {
      dates: @dates,
      roles:,
      people: @people.map(&:to_h),
    }.transform_keys(&:to_s)

    File.write(filepath, output.to_yaml)
  end
end
