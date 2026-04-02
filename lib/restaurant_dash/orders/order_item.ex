defmodule RestaurantDash.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_items" do
    field :name, :string
    field :quantity, :integer, default: 1
    field :unit_price, :integer, default: 0
    field :modifiers_json, :string, default: "[]"
    field :line_total, :integer, default: 0

    belongs_to :order, RestaurantDash.Orders.Order
    belongs_to :menu_item, RestaurantDash.Menu.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit_price,
      :modifiers_json,
      :line_total,
      :order_id,
      :menu_item_id
    ])
    |> validate_required([:name, :quantity, :unit_price, :line_total])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_number(:line_total, greater_than_or_equal_to: 0)
  end
end
