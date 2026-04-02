defmodule RestaurantDash.Kitchen do
  @moduledoc """
  Kitchen context — manages KDS order queue operations and prep time estimation.

  KDS status flow:
    new → accepted → preparing → ready → out_for_delivery → delivered
    any-active → cancelled (reject)

  All KDS transitions set kds_managed: true on the order, which prevents
  the Oban OrderLifecycleWorker from auto-transitioning the order.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Orders
  alias RestaurantDash.Orders.Order

  # Complexity multiplier — items with longer prep times add more to the estimate
  @queue_depth_penalty_minutes 2

  # ─── Queries ───────────────────────────────────────────────────────────────

  @doc "List orders relevant to KDS, grouped by status, for a restaurant."
  def list_kds_orders(restaurant_id) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], o.status in ^Order.kds_statuses())
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
    |> Repo.preload(:order_items)
  end

  @doc "List KDS orders grouped by status map."
  def list_kds_orders_grouped(restaurant_id) do
    orders = list_kds_orders(restaurant_id)
    base = Map.new(Order.kds_statuses(), &{&1, []})
    Enum.group_by(orders, & &1.status) |> then(&Map.merge(base, &1))
  end

  # ─── KDS Transitions ───────────────────────────────────────────────────────

  @doc """
  Accept a new order — moves from 'new' to 'accepted'.
  Sets kds_managed: true to prevent auto-transitions.
  """
  def accept_order(%Order{status: "new"} = order) do
    order
    |> Order.kds_transition_changeset("accepted")
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  def accept_order(%Order{status: status}) do
    {:error, "Cannot accept order with status '#{status}' (must be 'new')"}
  end

  @doc "Start preparing — moves from 'accepted' to 'preparing'."
  def start_preparing(%Order{status: "accepted"} = order) do
    order
    |> Order.kds_transition_changeset("preparing")
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  def start_preparing(%Order{status: status}) do
    {:error, "Cannot start preparing order with status '#{status}' (must be 'accepted')"}
  end

  @doc "Mark order ready for pickup — moves from 'preparing' to 'ready'."
  def mark_ready(%Order{status: "preparing"} = order) do
    order
    |> Order.kds_transition_changeset("ready")
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  def mark_ready(%Order{status: status}) do
    {:error, "Cannot mark ready order with status '#{status}' (must be 'preparing')"}
  end

  @doc """
  Reject/cancel an order — moves to 'cancelled' from any active status.
  In Phase 10 this will also send an SMS to the customer.
  """
  def reject_order(%Order{status: status} = order)
      when status in ~w(new accepted preparing) do
    order
    |> Order.kds_transition_changeset("cancelled")
    |> Repo.update()
    |> tap_broadcast(:order_updated)
  end

  def reject_order(%Order{status: status}) do
    {:error, "Cannot cancel order with status '#{status}'"}
  end

  # ─── Prep Time Estimation ──────────────────────────────────────────────────

  @doc """
  Calculate estimated prep time for an order.

  Formula:
    base = sum of prep_time_minutes for each ordered item (weighted by quantity)
    queue_penalty = @queue_depth_penalty_minutes * number of active (accepted/preparing) orders
    total = max(base, 5) + queue_penalty

  Returns minutes as an integer.
  """
  def calculate_prep_time(order_items, restaurant_id) when is_list(order_items) do
    base_minutes = calculate_base_prep_time(order_items)
    queue_depth = count_active_kds_orders(restaurant_id)
    penalty = queue_depth * @queue_depth_penalty_minutes
    max(base_minutes, 5) + penalty
  end

  @doc "Calculate prep time for order_items using preloaded menu items."
  def calculate_base_prep_time(order_items) do
    order_items
    |> Enum.reduce(0, fn item, acc ->
      # Try to get prep_time_minutes from menu_item association
      prep_mins =
        case item do
          %{menu_item: %{prep_time_minutes: mins}} when is_integer(mins) ->
            mins

          %{menu_item_id: _id} ->
            # When menu_item is not preloaded, fall back to default
            5

          _ ->
            5
        end

      acc + prep_mins * (item.quantity || 1)
    end)
  end

  @doc """
  Store estimated prep time on an order.
  Also calculates and saves when called from create_order_from_cart flow.
  """
  def set_estimated_prep_time(%Order{} = order, minutes) do
    order
    |> Order.prep_time_changeset(minutes)
    |> Repo.update()
  end

  @doc "Calculate and format estimated ready time as a DateTime."
  def estimated_ready_at(%Order{estimated_prep_minutes: nil}), do: nil

  def estimated_ready_at(%Order{estimated_prep_minutes: mins, inserted_at: inserted_at}) do
    DateTime.add(inserted_at, mins * 60, :second)
  end

  @doc "Time since order was placed, in seconds."
  def seconds_since_placed(%Order{inserted_at: inserted_at}) do
    DateTime.diff(DateTime.utc_now(), inserted_at, :second)
  end

  @doc "Color urgency based on time since placed."
  def urgency_color(order) do
    seconds = seconds_since_placed(order)
    minutes = div(seconds, 60)

    cond do
      minutes >= 20 -> "red"
      minutes >= 10 -> "yellow"
      true -> "green"
    end
  end

  @doc "Whether an order is 'priority' — large order (>5 items) or waiting long."
  def priority_order?(order) do
    item_count = total_item_count(order)
    seconds = seconds_since_placed(order)
    item_count > 5 or seconds > 15 * 60
  end

  @doc "Total item count across all order_items (falls back to legacy items array)."
  def total_item_count(%Order{} = order) do
    order_items = Map.get(order, :order_items, [])

    cond do
      is_list(order_items) and length(order_items) > 0 ->
        Enum.sum(Enum.map(order_items, & &1.quantity))

      is_list(order.items) and length(order.items) > 0 ->
        length(order.items)

      true ->
        0
    end
  end

  def total_item_count(_), do: 0

  # ─── Private ───────────────────────────────────────────────────────────────

  defp count_active_kds_orders(nil), do: 0

  defp count_active_kds_orders(restaurant_id) do
    Order
    |> where([o], o.restaurant_id == ^restaurant_id)
    |> where([o], o.status in ~w(accepted preparing))
    |> Repo.aggregate(:count, :id)
  end

  defp tap_broadcast({:ok, order} = result, event) do
    try do
      Orders.broadcast(event, order)
    rescue
      ArgumentError -> :ok
    end

    result
  end

  defp tap_broadcast(result, _event), do: result
end
