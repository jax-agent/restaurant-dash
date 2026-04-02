defmodule RestaurantDash.Repo.Migrations.CreateDriverProfiles do
  use Ecto.Migration

  def change do
    create table(:driver_profiles) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :vehicle_type, :string, default: "car", null: false
      add :license_plate, :string
      add :phone, :string
      add :is_available, :boolean, default: false, null: false
      add :is_approved, :boolean, default: false, null: false
      add :status, :string, default: "offline", null: false
      add :current_lat, :float
      add :current_lng, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:driver_profiles, [:user_id])
    create index(:driver_profiles, [:is_available])
    create index(:driver_profiles, [:status])
  end
end
