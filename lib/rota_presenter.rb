class RotaPresenter
  def initialize(filepath:)
    rota = YAML.load_file(filepath, symbolize_names: true)
    @dates = rota[:dates]
    @people = rota[:people].map { |person_data| Person.new(**person_data) }
    @roles_config = rota[:roles]
  end

  def to_csv
    roles = @roles_config.keys
    csv_lines = []

    columns = %w[date] + roles
    csv_lines = [columns]
    @dates.each do |date|
      row = columns.map do |column|
        if column == "date"
          date
        else
          person = @people.find { |candidate| candidate.assigned_shifts.include?({ date:, role: column }) }
          person.nil? ? "" : person.name
        end
      end
      csv_lines << row
    end

    csv_lines.map { |row| row.join(",") }.join("\n")
  end
end
