require_relative "../roles"

module Algorithms
  class Daily
    def self.fill_slots!(people:, dates:, roles_config:)
      roles_config = Roles.new(config: roles_config)
      people_queue = people

      dates.each do |date|
        day_of_week = Date.parse(date).strftime("%A")

        roles_to_fill = if %w[Saturday Sunday].include?(day_of_week)
                          roles_config.by_type(%i[weekends])
                        else
                          roles_config.by_type(%i[weekdays weeknights])
                        end

        roles_to_fill.each do |role|
          available_candidates = people_queue.select { |person| person.availability(date:).include?(role) }
          if available_candidates.empty?
            puts "NOBODY ABLE TO FILL #{role} on #{date}"
            break
          end

          person_to_assign = available_candidates.first
          person_to_assign.assign(role:, date:)
          people_queue.sort_by! { |person| roles_config.value_of_shifts(person.assigned_shifts) }
        end
      end
    end
  end
end
