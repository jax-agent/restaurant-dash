defmodule RestaurantDash.Repo.Migrations.AddSquareFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :square_order_id, :string
      add :payment_provider, :string, default: "stripe"
    end
  end
end
