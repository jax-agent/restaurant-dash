defmodule RestaurantDash.Cart do
  @moduledoc """
  Pure functional Cart module.

  A cart belongs to a single restaurant and holds a list of CartItems.
  Cart totals are calculated on demand, using a configurable tax rate.

  Money values are always stored as integer cents.
  """

  alias __MODULE__
  alias RestaurantDash.Cart.CartItem

  @default_tax_rate 0.08875
  @delivery_fee_cents 299

  @type t :: %Cart{
          restaurant_id: integer() | nil,
          items: [CartItem.t()]
        }

  defstruct restaurant_id: nil, items: []

  # ─── Construction ─────────────────────────────────────────────────────────

  @doc "Create a new empty cart for a restaurant."
  def new(restaurant_id) do
    %Cart{restaurant_id: restaurant_id, items: []}
  end

  # ─── Mutations ────────────────────────────────────────────────────────────

  @doc """
  Add an item to the cart. If the same menu_item_id with the same selected
  modifiers already exists, increments quantity; otherwise appends a new entry.
  """
  def add_item(%Cart{} = cart, attrs) do
    item = CartItem.new(attrs)
    key = item_key(item)

    case find_item_index(cart, key) do
      nil ->
        %{cart | items: cart.items ++ [item]}

      index ->
        updated =
          List.update_at(cart.items, index, fn existing ->
            CartItem.set_quantity(existing, existing.quantity + item.quantity)
          end)

        %{cart | items: updated}
    end
  end

  @doc "Remove an item by its cart key (menu_item_id + sorted modifier ids)."
  def remove_item(%Cart{} = cart, key) do
    %{cart | items: Enum.reject(cart.items, &(item_key(&1) == key))}
  end

  @doc "Update quantity for an item by key. Quantity <= 0 removes the item."
  def update_quantity(%Cart{} = cart, key, qty) when is_integer(qty) do
    if qty <= 0 do
      remove_item(cart, key)
    else
      updated =
        Enum.map(cart.items, fn item ->
          if item_key(item) == key, do: CartItem.set_quantity(item, qty), else: item
        end)

      %{cart | items: updated}
    end
  end

  # ─── Totals ───────────────────────────────────────────────────────────────

  @doc """
  Calculate cart totals.

  Options:
  - `:tax_rate` — decimal tax rate (default #{@default_tax_rate})
  - `:delivery_fee` — integer cents (default #{@delivery_fee_cents})
  - `:tip` — integer cents (default 0)

  Returns a map:
    %{subtotal: int, tax: int, delivery_fee: int, tip: int, total: int}
  """
  def calculate_totals(%Cart{} = cart, opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, @default_tax_rate)
    delivery_fee = Keyword.get(opts, :delivery_fee, @delivery_fee_cents)
    tip = Keyword.get(opts, :tip, 0)

    subtotal = Enum.sum(Enum.map(cart.items, & &1.line_total))
    tax = round(subtotal * tax_rate)
    total = subtotal + tax + delivery_fee + tip

    %{
      subtotal: subtotal,
      tax: tax,
      delivery_fee: delivery_fee,
      tip: tip,
      total: total
    }
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  @doc "Returns true if the cart has no items."
  def empty?(%Cart{items: []}), do: true
  def empty?(%Cart{}), do: false

  @doc "Returns the total count of items (summing quantities)."
  def item_count(%Cart{items: items}) do
    Enum.sum(Enum.map(items, & &1.quantity))
  end

  @doc """
  Unique key for a cart item: menu_item_id (or name fallback) + sorted selected modifier ids.
  Used to determine if an add_item call should merge or append.
  """
  def item_key(%CartItem{menu_item_id: mid, name: name, selected_modifiers: mods}) do
    sorted_ids =
      mods
      |> Enum.flat_map(fn
        {_group_id, %MapSet{} = ids} -> MapSet.to_list(ids)
        {_group_id, id} when is_integer(id) -> [id]
        _ -> []
      end)
      |> Enum.sort()

    # Use menu_item_id if present, otherwise fall back to name
    id = mid || name
    {id, sorted_ids}
  end

  def item_key(%{menu_item_id: mid, name: name, selected_modifiers: mods}) do
    item_key(%CartItem{menu_item_id: mid, name: name, selected_modifiers: mods})
  end

  # ─── Private ──────────────────────────────────────────────────────────────

  defp find_item_index(%Cart{items: items}, key) do
    Enum.find_index(items, &(item_key(&1) == key))
  end
end
