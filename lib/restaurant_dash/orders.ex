defmodule RestaurantDash.Orders do
  @moduledoc """
  The Orders context. All queries support optional restaurant scoping.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Orders.Order
  alias RestaurantDash.Orders.OrderItem
  alias RestaurantDash.Cart

  @pubsub RestaurantDash.PubSub
  @topic "orders"

  # ─── PubSub ────────────────────────────────────────────────────────────────

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  def subscribe(restaurant_id) when is_integer(restaurant_id) do
    Phoenix.PubSub.subscribe(@pubsub, "orders:#{restaurant_id}")
  end

  def broadcast(event, order) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, order})

    if order.restaurant_id do
      Phoenix.PubSub.broadcast(@pubsub, "orders:#{order.restaurant_id}", {event, order})
    end
  end

  # ─── Queries ───────────────────────────────────────────────────────────────

  @doc "Lists orders, optionally scoped to a restaurant."
  def list_orders(restaurant_id \\ nil) do
    Order
    |> scope_by_restaurant(restaurant_id)
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
  end

  @doc "Lists orders by status, optionally scoped to a restaurant."
  def list_orders_by_status(status, restaurant_id \\ nil) do
    Order
    |> where([o], o.status == ^status)
    |> scope_by_restaurant(restaurant_id)
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
  end

  @doc "Lists active deliveries (out_for_delivery), optionally scoped to a restaurant."
  def list_active_deliveries(restaurant_id \\ nil) do
    Order
    |> where([o], o.status == "out_for_delivery")
    |> scope_by_restaurant(restaurant_id)
    |> Repo.all()
  end

  def get_order!(id), do: Repo.get!(Order, id)

  def get_order(id), do: Repo.get(Order, id)

  @doc "Gets an order, scoped to a restaurant to prevent cross-tenant access."
  def get_order_for_restaurant!(id, restaurant_id) do
    Order
    |> where([o], o.id == ^id and o.restaurant_id == ^restaurant_id)
    |> Repo.one!()
  end

  # ─── Stats ─────────────────────────────────────────────────────────────────

  @doc "Count orders by status, optionally scoped to a restaurant."
  def count_by_status(restaurant_id \\ nil) do
    Order
    |> scope_by_restaurant(restaurant_id)
    |> group_by([o], o.status)
    |> select([o], {o.status, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count orders placed today, optionally scoped to a restaurant."
  def count_today(restaurant_id \\ nil) do
    today_start = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    Order
    |> scope_by_restaurant(restaurant_id)
    |> where([o], o.inserted_at >= ^today_start)
    |> Repo.aggregate(:count, :id)
  end

  @doc "Total order count, optionally scoped to a restaurant."
  def count_total(restaurant_id \\ nil) do
    Order
    |> scope_by_restaurant(restaurant_id)
    |> Repo.aggregate(:count, :id)
  end

  # ─── Mutations ─────────────────────────────────────────────────────────────

  def create_order(attrs \\ %{}) do
    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert()
    |> tap_broadcast(:order_created)
  end

  def update_order(%Order{} = order, attrs) do
    order
    |> Order.changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  def transition_order(%Order{} = order, new_status) do
    order
    |> Order.status_changeset(new_status)
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  def update_order_position(%Order{} = order, lat, lng) do
    order
    |> Order.position_changeset(lat, lng)
    |> Repo.update()
    |> tap_broadcast(:order_position_updated)
  end

  def delete_order(%Order{} = order) do
    Repo.delete(order)
  end

  @doc """
  Create an order from a cart + customer info. Wraps in a transaction.

  attrs must include:
  - customer_name, customer_email, customer_phone, delivery_address, restaurant_id

  Returns {:ok, order} with preloaded order_items, or {:error, changeset}.
  """
  def create_order_from_cart(%Cart{} = cart, attrs, opts \\ []) do
    tip = Keyword.get(opts, :tip, 0)
    totals = Cart.calculate_totals(cart, tip: tip)

    order_attrs =
      attrs
      |> Map.put(:subtotal, totals.subtotal)
      |> Map.put(:tax_amount, totals.tax)
      |> Map.put(:delivery_fee, totals.delivery_fee)
      |> Map.put(:tip_amount, totals.tip)
      |> Map.put(:total_amount, totals.total)
      |> Map.put(:status, "new")

    Repo.transaction(fn ->
      with {:ok, order} <-
             %Order{}
             |> Order.cart_order_changeset(order_attrs)
             |> Repo.insert(),
           :ok <- insert_order_items(order, cart.items) do
        order = Repo.preload(order, :order_items)
        broadcast(:order_created, order)
        order
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Get order with order_items preloaded."
  def get_order_with_items!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload(:order_items)
  end

  def get_order_with_items(id) do
    case Repo.get(Order, id) do
      nil -> nil
      order -> Repo.preload(order, :order_items)
    end
  end

  # ─── Changeset ─────────────────────────────────────────────────────────────

  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  # ─── Private ───────────────────────────────────────────────────────────────

  defp scope_by_restaurant(query, nil), do: query

  defp scope_by_restaurant(query, restaurant_id) do
    where(query, [o], o.restaurant_id == ^restaurant_id)
  end

  defp tap_broadcast({:ok, order} = result, event) do
    # Guard against PubSub not being started (e.g. in Release.eval context)
    try do
      broadcast(event, order)
    rescue
      ArgumentError -> :ok
    end

    result
  end

  defp tap_broadcast(result, _event), do: result

  defp insert_order_items(_order, []), do: :ok

  defp insert_order_items(order, items) do
    result =
      Enum.reduce_while(items, :ok, fn cart_item, :ok ->
        attrs = %{
          order_id: order.id,
          menu_item_id: cart_item.menu_item_id,
          name: cart_item.name,
          quantity: cart_item.quantity,
          unit_price: Cart.CartItem.unit_price(cart_item),
          modifiers_json: encode_modifiers(cart_item.modifier_names),
          line_total: cart_item.line_total
        }

        case %OrderItem{} |> OrderItem.changeset(attrs) |> Repo.insert() do
          {:ok, _} -> {:cont, :ok}
          {:error, cs} -> {:halt, {:error, cs}}
        end
      end)

    case result do
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  defp encode_modifiers(modifier_names) when is_list(modifier_names) do
    modifier_names
    |> Enum.map(fn
      {name, price_adj} -> %{name: name, price_adjustment: price_adj}
      name when is_binary(name) -> %{name: name, price_adjustment: 0}
    end)
    |> Jason.encode!()
  rescue
    _ -> "[]"
  end

  defp encode_modifiers(_), do: "[]"
end
