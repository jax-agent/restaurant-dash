defmodule RestaurantDash.Workers.DriverSimulationWorker do
  @moduledoc """
  Simulates driver movement by nudging lat/lng for orders that are out_for_delivery.
  Runs every 30 seconds via Oban cron.
  """

  use Oban.Worker, queue: :drivers

  alias RestaurantDash.Orders

  # Small nudge range in degrees (~11 meters per 0.0001 degree)
  @nudge_range 0.0005

  @impl Oban.Worker
  def perform(_job) do
    active = Orders.list_active_deliveries()

    Enum.each(active, fn order ->
      if order.lat && order.lng do
        new_lat = order.lat + random_nudge()
        new_lng = order.lng + random_nudge()
        Orders.update_order_position(order, new_lat, new_lng)
      end
    end)

    :ok
  end

  defp random_nudge do
    (:rand.uniform() - 0.5) * 2 * @nudge_range
  end
end
