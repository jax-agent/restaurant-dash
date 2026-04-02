defmodule RestaurantDash.Repo.Migrations.AddAutoDispatchToRestaurants do
  use Ecto.Migration

  def change do
    alter table(:restaurants) do
      add :auto_dispatch_enabled, :boolean, default: false, null: false
      add :lat, :float
      add :lng, :float
    end
  end
end
