defmodule RestaurantDash.Repo.Migrations.AddLocationAtToDriverProfiles do
  use Ecto.Migration

  def change do
    alter table(:driver_profiles) do
      add :last_location_at, :utc_datetime
    end
  end
end
