defmodule RestaurantDash.Repo.Migrations.CreateOrderItems do
  use Ecto.Migration

  def change do
    create table(:order_items) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :menu_item_id, references(:menu_items, on_delete: :nilify_all)
      add :name, :string, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_price, :integer, null: false, default: 0
      add :modifiers_json, :text, default: "[]"
      add :line_total, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:menu_item_id])
  end
end
