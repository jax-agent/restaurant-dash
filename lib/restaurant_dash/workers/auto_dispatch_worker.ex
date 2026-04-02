defmodule RestaurantDash.Workers.AutoDispatchWorker do
  @moduledoc """
  Oban worker for auto-dispatching ready orders to the nearest available driver.

  Triggered when an order reaches "ready" status (from KDS).
  - Finds nearest available driver using Haversine distance.
  - Assigns if found; otherwise retries after 30 seconds.
  - Owner can override by manually assigning (order.driver_id set).
  - Only runs if restaurant has auto_dispatch_enabled: true.
  """

  use Oban.Worker,
    queue: :dispatch,
    max_attempts: 50,
    unique: [period: :infinity, states: [:available, :scheduled, :executing], keys: [:order_id]]

  alias RestaurantDash.{Orders, Drivers, Repo}
  alias RestaurantDash.Orders.Order
  alias RestaurantDash.Tenancy.Restaurant

  @retry_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    order = Orders.get_order(order_id)

    cond do
      # Order was deleted
      is_nil(order) ->
        :ok

      # Order already has a driver (manual override happened)
      not is_nil(order.driver_id) ->
        :ok

      # Order is no longer in "ready" status — skip
      order.status != "ready" ->
        :ok

      true ->
        attempt_dispatch(order)
    end
  end

  @doc "Schedule auto-dispatch for an order that just became ready."
  def schedule_for(%Order{id: order_id, restaurant_id: restaurant_id, status: "ready"}) do
    restaurant = Repo.get(Restaurant, restaurant_id)

    if restaurant && restaurant.auto_dispatch_enabled do
      %{"order_id" => order_id}
      |> new()
      |> Oban.insert()
    else
      {:ok, :disabled}
    end
  end

  def schedule_for(_order), do: {:ok, :skipped}

  # ─── Private ───────────────────────────────────────────────────────────────

  defp attempt_dispatch(order) do
    restaurant = Repo.get(RestaurantDash.Tenancy.Restaurant, order.restaurant_id)

    # Get restaurant lat/lng as the "from" point
    {rest_lat, rest_lng} = restaurant_coords(restaurant, order)

    case Drivers.find_nearest_driver(rest_lat, rest_lng) do
      nil ->
        # No drivers available — retry in 30 seconds
        {:snooze, @retry_seconds}

      driver_profile ->
        assign_and_update(order, driver_profile)
    end
  end

  defp assign_and_update(order, driver_profile) do
    with {:ok, _order} <- Orders.assign_driver(order, driver_profile.user_id),
         {:ok, _profile} <- Drivers.set_status(driver_profile, "on_delivery") do
      :ok
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp restaurant_coords(%Restaurant{lat: lat, lng: lng}, _order)
       when is_float(lat) and is_float(lng),
       do: {lat, lng}

  defp restaurant_coords(_restaurant, %Order{lat: lat, lng: lng})
       when is_float(lat) and is_float(lng),
       do: {lat, lng}

  # Default fallback — no location data, pick first available driver
  defp restaurant_coords(_restaurant, _order), do: {0.0, 0.0}
end
