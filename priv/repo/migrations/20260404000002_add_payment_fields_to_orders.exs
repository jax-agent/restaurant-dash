defmodule RestaurantDash.Repo.Migrations.AddPaymentFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :payment_status, :string, default: "pending"
      add :payment_intent_id, :string
    end

    create index(:orders, [:payment_intent_id])
  end
end
