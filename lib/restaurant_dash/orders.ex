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
  Assign a driver to a ready order.
  Sets order status to "assigned" and records assigned_at timestamp.
  """
  def assign_driver(%Order{} = order, driver_id) do
    order
    |> Order.assign_driver_changeset(driver_id)
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  @doc """
  Update delivery status (picked_up or delivered).
  For use by drivers to update their delivery progress.
  """
  def update_delivery_status(%Order{} = order, status)
      when status in ["picked_up", "out_for_delivery", "delivered"] do
    order
    |> Order.delivery_transition_changeset(status)
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  @doc "List orders assigned to a specific driver."
  def list_driver_orders(driver_id) do
    Order
    |> where([o], o.driver_id == ^driver_id)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
    |> Repo.preload(:order_items)
  end

  @doc "Get the current active delivery for a driver (assigned or picked_up)."
  def get_active_delivery(driver_id) do
    Order
    |> where([o], o.driver_id == ^driver_id and o.status in ["assigned", "picked_up"])
    |> order_by([o], desc: o.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      order -> Repo.preload(order, :order_items)
    end
  end

  @doc "List orders in the dispatch queue (status: ready, no driver assigned)."
  def list_dispatch_queue(restaurant_id \\ nil) do
    Order
    |> where([o], o.status == "ready" and is_nil(o.driver_id))
    |> scope_by_restaurant(restaurant_id)
    |> order_by([o], asc: o.ready_at)
    |> Repo.all()
  end

  @doc "Count today's deliveries for a driver."
  def count_driver_deliveries_today(driver_id) do
    today_start = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    Order
    |> where([o], o.driver_id == ^driver_id and o.status == "delivered")
    |> where([o], o.delivered_at >= ^today_start)
    |> Repo.aggregate(:count, :id)
  end

  @doc "Sum today's tips for a driver."
  def sum_driver_tips_today(driver_id) do
    today_start = DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

    Order
    |> where([o], o.driver_id == ^driver_id and o.status == "delivered")
    |> where([o], o.delivered_at >= ^today_start)
    |> Repo.aggregate(:sum, :tip_amount) || 0
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

  @doc "Submit proof of delivery (photo and/or signature)."
  def submit_proof_of_delivery(%Order{} = order, attrs) do
    order
    |> Order.proof_of_delivery_changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  @doc "Submit a driver rating for a delivered order."
  def submit_driver_rating(%Order{} = order, rating, comment \\ "") do
    order
    |> Order.driver_rating_changeset(rating, comment)
    |> Repo.update()
  end

  @doc "Get the average driver rating for a given driver user_id."
  def get_driver_average_rating(driver_user_id) do
    result =
      Order
      |> where([o], o.driver_id == ^driver_user_id and not is_nil(o.driver_rating))
      |> select([o], {avg(o.driver_rating), count(o.id)})
      |> Repo.one()

    case result do
      {nil, 0} -> {nil, 0}
      {avg, count} -> {Decimal.to_float(avg), count}
    end
  end

  @doc "List delivered orders with ratings for driver reporting."
  def list_orders_with_ratings(restaurant_id) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id and not is_nil(o.driver_rating))
    |> order_by([o], desc: o.delivered_at)
    |> Repo.all()
  end

  # ─── Phase 12: Scheduled Orders ──────────────────────────────────────────────

  @doc "List scheduled (future) orders for a restaurant."
  def list_scheduled_orders(restaurant_id) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id and o.status == "scheduled")
    |> order_by([o], asc: o.scheduled_for)
    |> Repo.all()
  end

  @doc """
  Validates that a scheduled_for datetime is at least min_minutes ahead and
  within max_days in the future. Returns :ok or {:error, reason}.
  """
  def validate_scheduled_time(scheduled_for, min_minutes \\ 30, max_days \\ 7) do
    now = DateTime.utc_now()
    min_dt = DateTime.add(now, min_minutes * 60, :second)
    max_dt = DateTime.add(now, max_days * 24 * 3600, :second)

    cond do
      DateTime.compare(scheduled_for, min_dt) == :lt ->
        {:error, "Scheduled time must be at least #{min_minutes} minutes from now"}

      DateTime.compare(scheduled_for, max_dt) == :gt ->
        {:error, "Scheduled time cannot be more than #{max_days} days in the future"}

      true ->
        :ok
    end
  end

  # ─── Phase 12: Reviews ────────────────────────────────────────────────────────

  @doc "Submit a restaurant review for a delivered order."
  def submit_restaurant_review(%Order{} = order, rating, review \\ "") do
    order
    |> Order.restaurant_review_changeset(rating, review)
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  @doc "Add owner response to a review."
  def respond_to_review(%Order{} = order, response_text) do
    order
    |> Ecto.Changeset.change(%{review_response: response_text})
    |> Repo.update()
  end

  @doc "Get average restaurant rating and count."
  def get_restaurant_rating(restaurant_id) do
    result =
      Order
      |> where([o], o.restaurant_id == ^restaurant_id and not is_nil(o.restaurant_rating))
      |> select([o], {avg(o.restaurant_rating), count(o.id)})
      |> Repo.one()

    case result do
      {nil, 0} -> {nil, 0}
      {avg, count} -> {Decimal.to_float(avg), count}
    end
  end

  @doc "List reviewed orders (with restaurant_rating) for a restaurant."
  def list_reviews(restaurant_id, limit \\ 20) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id and not is_nil(o.restaurant_rating))
    |> order_by([o], desc: o.delivered_at)
    |> limit(^limit)
    |> Repo.all()
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
