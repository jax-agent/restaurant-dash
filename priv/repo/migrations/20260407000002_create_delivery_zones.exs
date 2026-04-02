defmodule RestaurantDash.Repo.Migrations.CreateDeliveryZones do
  use Ecto.Migration

  def change do
    create table(:delivery_zones) do
      add :restaurant_id, references(:restaurants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :polygon, :jsonb, null: false, default: "[]"
      add :delivery_fee, :integer, null: false, default: 0
      add :min_order, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:delivery_zones, [:restaurant_id])
  end
end
