defmodule RestaurantDash.Repo.Migrations.AddCloverOrderIdToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :clover_order_id, :string
    end
  end
end
