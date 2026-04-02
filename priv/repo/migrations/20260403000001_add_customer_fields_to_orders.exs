defmodule RestaurantDash.Repo.Migrations.AddCustomerFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :customer_email, :string
      add :customer_phone, :string
      add :subtotal, :integer, default: 0
      add :tax_amount, :integer, default: 0
      add :delivery_fee, :integer, default: 0
      add :tip_amount, :integer, default: 0
      add :total_amount, :integer, default: 0
    end
  end
end
