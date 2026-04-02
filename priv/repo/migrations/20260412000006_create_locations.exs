defmodule RestaurantDash.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :address, :string, null: false
      add :city, :string
      add :state, :string
      add :zip, :string
      add :phone, :string
      add :lat, :float
      add :lng, :float
      add :is_active, :boolean, default: true, null: false
      add :is_primary, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:locations, [:restaurant_id])
    create index(:locations, [:restaurant_id, :is_primary])

    # Add location_id to orders (optional — null means primary/default)
    alter table(:orders) do
      add :location_id, references(:locations, on_delete: :nilify_all)
    end
  end
end
