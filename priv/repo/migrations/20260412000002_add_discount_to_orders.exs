defmodule RestaurantDash.Repo.Migrations.AddDiscountToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :discount_amount, :integer, default: 0
      add :promo_code, :string
    end
  end
end
