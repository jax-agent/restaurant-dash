defmodule RestaurantDash.Repo.Migrations.AddDriverFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      # Driver assignment
      add :driver_id, references(:users, on_delete: :nilify_all)

      # Delivery timestamps
      add :assigned_at, :utc_datetime
      add :picked_up_at, :utc_datetime
      add :delivered_at, :utc_datetime
    end

    # Update valid statuses: add "assigned" and "picked_up"
    # (statuses are validated in Elixir, not DB constraints — no migration needed for that)

    create index(:orders, [:driver_id])
  end
end
