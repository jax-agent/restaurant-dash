defmodule RestaurantDash.Cart.Store do
  @moduledoc """
  ETS-backed store for shopping carts.

  Carts are keyed by a `cart_id` UUID that lives in the browser session.
  Entries expire after `@ttl_ms` milliseconds of inactivity.

  Start this GenServer in your application supervisor.
  """

  use GenServer

  alias RestaurantDash.Cart

  @table :cart_store
  @ttl_ms :timer.hours(6)
  @sweep_interval_ms :timer.minutes(10)

  # ─── Public API ───────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Fetch a cart by ID. Returns `%Cart{}` or a new empty cart."
  def get(cart_id, restaurant_id \\ nil) do
    case :ets.lookup(@table, cart_id) do
      [{^cart_id, cart, _expires_at}] ->
        :ets.insert(@table, {cart_id, cart, new_expiry()})
        cart

      [] ->
        Cart.new(restaurant_id)
    end
  end

  @doc "Persist a cart for a cart_id. Returns the saved cart."
  def put(cart_id, %Cart{} = cart) do
    :ets.insert(@table, {cart_id, cart, new_expiry()})
    cart
  end

  @doc "Delete a cart by ID (called after order placement)."
  def delete(cart_id) do
    :ets.delete(@table, cart_id)
    :ok
  end

  # ─── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  # ─── Private ──────────────────────────────────────────────────────────────

  defp new_expiry, do: System.monotonic_time(:millisecond) + @ttl_ms

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end
end
