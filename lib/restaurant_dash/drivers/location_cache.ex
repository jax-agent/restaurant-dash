defmodule RestaurantDash.Drivers.LocationCache do
  @moduledoc """
  ETS-backed cache for real-time driver GPS locations.

  Avoids DB hits for frequent location updates.
  Stores: {driver_id, lat, lng}
  """

  use GenServer

  @table :driver_location_cache

  # ─── Public API ─────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store or update a driver's location."
  def put(driver_id, lat, lng) when is_number(lat) and is_number(lng) do
    :ets.insert(@table, {driver_id, lat, lng})
    :ok
  end

  @doc "Retrieve a driver's location. Returns {:ok, {lat, lng}} or :not_found."
  def get(driver_id) do
    case :ets.lookup(@table, driver_id) do
      [{^driver_id, lat, lng}] -> {:ok, {lat, lng}}
      [] -> :not_found
    end
  end

  @doc "Return all driver locations as [{driver_id, lat, lng}]."
  def list_all do
    :ets.tab2list(@table)
  end

  @doc "Remove a driver from cache (e.g., when they go offline)."
  def delete(driver_id) do
    :ets.delete(@table, driver_id)
    :ok
  end

  @doc "Clear all entries (test helper)."
  def clear_all do
    :ets.delete_all_objects(@table)
    :ok
  end

  # ─── GenServer Callbacks ────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
