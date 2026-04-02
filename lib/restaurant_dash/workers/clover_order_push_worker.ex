defmodule RestaurantDash.Workers.CloverOrderPushWorker do
  @moduledoc """
  Oban worker that pushes an order to Clover POS.
  Retries automatically on failure — order is still valid in our system
  if Clover push fails.
  """

  use Oban.Worker,
    queue: :clover,
    max_attempts: 5

  alias RestaurantDash.Orders
  alias RestaurantDash.Tenancy
  alias RestaurantDash.Integrations.Clover

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Orders.get_order(order_id)

    if is_nil(order) do
      Logger.warning("[CloverOrderPushWorker] Order #{order_id} not found, skipping")
      :ok
    else
      restaurant = Tenancy.get_restaurant(order.restaurant_id)

      cond do
        is_nil(restaurant) ->
          Logger.warning("[CloverOrderPushWorker] Restaurant not found for order #{order_id}")
          :ok

        not Clover.connected?(restaurant) ->
          # Restaurant not connected to Clover — skip silently
          :ok

        not is_nil(order.clover_order_id) ->
          # Already pushed
          :ok

        true ->
          case Clover.push_order(order, restaurant) do
            {:ok, clover_id} ->
              Logger.info(
                "[CloverOrderPushWorker] Order #{order_id} pushed to Clover: #{clover_id}"
              )

              :ok

            {:error, reason} ->
              Logger.error(
                "[CloverOrderPushWorker] Failed to push order #{order_id}: #{inspect(reason)}"
              )

              # Raise to trigger Oban retry
              {:error, reason}
          end
      end
    end
  end

  @doc "Enqueue a Clover push for a new order."
  def enqueue(order_id) do
    %{"order_id" => order_id}
    |> new()
    |> Oban.insert()
  end
end
