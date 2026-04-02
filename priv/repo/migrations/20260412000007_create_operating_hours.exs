defmodule RestaurantDash.Repo.Migrations.CreateOperatingHours do
  use Ecto.Migration

  def change do
    create table(:operating_hours) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :day_of_week, :integer, null: false
      add :open_time, :time, null: false
      add :close_time, :time, null: false
      add :is_closed, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:operating_hours, [:restaurant_id])
    create unique_index(:operating_hours, [:restaurant_id, :day_of_week])

    create table(:closures) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:closures, [:restaurant_id])
    create unique_index(:closures, [:restaurant_id, :date])
  end
end
