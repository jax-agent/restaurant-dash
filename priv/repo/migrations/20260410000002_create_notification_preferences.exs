defmodule RestaurantDash.Repo.Migrations.CreateNotificationPreferences do
  use Ecto.Migration

  def change do
    alter table(:restaurants) do
      add :notification_preferences, :map, default: %{}
    end
  end
end
