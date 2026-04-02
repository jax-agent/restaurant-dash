defmodule RestaurantDash.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :customer_name, :string, null: false
      add :phone, :string
      add :items, {:array, :string}, null: false, default: []
      add :status, :string, null: false, default: "new"
      add :delivery_address, :string
      add :lat, :float
      add :lng, :float

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:status])
    create index(:orders, [:inserted_at])
  end
end
