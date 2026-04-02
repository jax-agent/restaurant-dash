defmodule RestaurantDash.Repo.Migrations.AddScheduledForToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :scheduled_for, :utc_datetime
    end

    create index(:orders, [:scheduled_for])
  end
end
