defmodule RestaurantDash.Orders do
  @moduledoc """
  The Orders context.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Orders.Order

  @pubsub RestaurantDash.PubSub
  @topic "orders"

  # ─── PubSub ────────────────────────────────────────────────────────────────

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  def broadcast(event, order) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, order})
  end

  # ─── Queries ───────────────────────────────────────────────────────────────

  def list_orders do
    Order
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
  end

  def list_orders_by_status(status) do
    Order
    |> where([o], o.status == ^status)
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
  end

  def list_active_deliveries do
    Order
    |> where([o], o.status == "out_for_delivery")
    |> Repo.all()
  end

  def get_order!(id), do: Repo.get!(Order, id)

  def get_order(id), do: Repo.get(Order, id)

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

  # ─── Changeset ─────────────────────────────────────────────────────────────

  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  # ─── Stats ─────────────────────────────────────────────────────────────────

  def count_by_status do
    Order
    |> group_by([o], o.status)
    |> select([o], {o.status, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ─── Private ───────────────────────────────────────────────────────────────

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
end
