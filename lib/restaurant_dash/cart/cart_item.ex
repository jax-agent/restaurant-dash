defmodule RestaurantDash.Cart.CartItem do
  @moduledoc """
  A single line item in a cart.

  Fields:
  - menu_item_id: integer
  - name: string
  - quantity: integer
  - base_price: integer cents
  - selected_modifiers: map of group_id => modifier_id (radio) or MapSet of modifier_ids (checkbox)
  - modifier_names: list of {name, price_adjustment} tuples for display
  - line_total: integer cents (base_price * quantity + modifier adjustments * quantity)
  """

  alias __MODULE__

  @type t :: %CartItem{
          menu_item_id: integer(),
          name: String.t(),
          quantity: integer(),
          base_price: integer(),
          selected_modifiers: map(),
          modifier_names: list(),
          line_total: integer()
        }

  defstruct [
    :menu_item_id,
    :name,
    quantity: 1,
    base_price: 0,
    selected_modifiers: %{},
    modifier_names: [],
    line_total: 0
  ]

  @doc """
  Build a CartItem from attrs. Calculates line_total from base_price, modifier adjustments,
  and quantity.

  attrs:
  - menu_item_id: required
  - name: required
  - quantity: default 1
  - base_price: required (integer cents)
  - selected_modifiers: map of group_id => modifier_id | MapSet
  - modifier_names: [{name, price_adj}] list (for display only)
  - modifier_price_adjustment: pre-computed total modifier price adjustment in cents
  """
  def new(attrs) when is_map(attrs) do
    menu_item_id = Map.fetch!(attrs, :menu_item_id)
    name = Map.fetch!(attrs, :name)
    quantity = Map.get(attrs, :quantity, 1)
    base_price = Map.get(attrs, :base_price, 0)
    selected_modifiers = Map.get(attrs, :selected_modifiers, %{})
    modifier_names = Map.get(attrs, :modifier_names, [])

    # Accept pre-computed modifier price adjustment or compute 0
    modifier_adjustment = Map.get(attrs, :modifier_price_adjustment, 0)

    unit_price = base_price + modifier_adjustment
    line_total = unit_price * quantity

    %CartItem{
      menu_item_id: menu_item_id,
      name: name,
      quantity: quantity,
      base_price: base_price,
      selected_modifiers: selected_modifiers,
      modifier_names: modifier_names,
      line_total: line_total
    }
  end

  @doc "Update quantity and recalculate line_total."
  def set_quantity(%CartItem{} = item, qty) when is_integer(qty) and qty > 0 do
    unit_price = div(item.line_total, item.quantity)
    %{item | quantity: qty, line_total: unit_price * qty}
  end

  @doc "Returns the unit price (line_total / quantity)."
  def unit_price(%CartItem{line_total: lt, quantity: q}), do: div(lt, q)
end
