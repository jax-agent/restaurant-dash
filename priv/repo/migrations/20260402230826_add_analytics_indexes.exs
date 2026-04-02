defmodule RestaurantDash.Repo.Migrations.AddAnalyticsIndexes do
  use Ecto.Migration

  def change do
    # For revenue_summary, orders_by_status, orders_by_hour, orders_by_day
    create_if_not_exists index(:orders, [:restaurant_id, :inserted_at])
    create_if_not_exists index(:orders, [:restaurant_id, :status, :inserted_at])

    # For delivery metrics
    create_if_not_exists index(:orders, [:restaurant_id, :status, :delivered_at])

    # For order items analytics
    create_if_not_exists index(:order_items, [:menu_item_id])
    create_if_not_exists index(:order_items, [:order_id, :menu_item_id])
  end
end
