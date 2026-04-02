defmodule RestaurantDash.Workers.SquareOrderPushWorker do
  @moduledoc """
  Oban worker that pushes an order to Square POS via Orders API.
  Retries automatically on failure — order is still valid in our system
  if Square push fails.
  """

  use Oban.Worker,
    queue: :square,
    max_attempts: 5

  alias RestaurantDash.Orders
  alias RestaurantDash.Tenancy
  alias RestaurantDash.Integrations.Square

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Orders.get_order(order_id)

    if is_nil(order) do
      Logger.warning("[SquareOrderPushWorker] Order #{order_id} not found, skipping")
      :ok
    else
      restaurant = Tenancy.get_restaurant(order.restaurant_id)

      cond do
        is_nil(restaurant) ->
          Logger.warning("[SquareOrderPushWorker] Restaurant not found for order #{order_id}")
          :ok

        not Square.connected?(restaurant) ->
          # Restaurant not connected to Square — skip silently
          :ok

        not is_nil(order.square_order_id) ->
          # Already pushed
          :ok

        true ->
          case Square.push_order(order, restaurant) do
            {:ok, square_id} ->
              Logger.info(
                "[SquareOrderPushWorker] Order #{order_id} pushed to Square: #{square_id}"
              )

              :ok

            {:error, reason} ->
              Logger.error(
                "[SquareOrderPushWorker] Failed to push order #{order_id}: #{inspect(reason)}"
              )

              # Raise to trigger Oban retry
              {:error, reason}
          end
      end
    end
  end

  @doc "Enqueue a Square push for a new order."
  def enqueue(order_id) do
    %{"order_id" => order_id}
    |> new()
    |> Oban.insert()
  end
end
