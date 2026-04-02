defmodule RestaurantDash.Workers.ScheduledOrderWorker do
  @moduledoc """
  Oban worker that activates scheduled orders at the right time.
  When a scheduled order's time arrives, it transitions from "scheduled" to "new"
  so the kitchen can see it.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias RestaurantDash.{Orders, Repo}
  alias RestaurantDash.Orders.Order

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Repo.get(Order, order_id)

    cond do
      is_nil(order) ->
        {:ok, :order_not_found}

      order.status != "scheduled" ->
        {:ok, :already_processed}

      true ->
        Orders.transition_order(order, "new")
        {:ok, :activated}
    end
  end

  @doc """
  Schedule an Oban job to activate the order at the scheduled_for time.
  """
  def schedule_for_order(%Order{id: id, scheduled_for: scheduled_at})
      when not is_nil(scheduled_at) do
    %{order_id: id}
    |> new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  def schedule_for_order(_order), do: {:ok, :not_scheduled}
end
