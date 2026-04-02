defmodule RestaurantDash.Workers.CloverInventorySyncWorker do
  @moduledoc """
  Oban worker that periodically syncs item availability from Clover.

  When items are marked unavailable (86'd) on Clover POS → we mark them
  unavailable in our menu too. When they come back → we restore availability.

  Default interval: every 5 minutes (configured in Oban cron queue).
  """

  use Oban.Worker,
    queue: :clover,
    max_attempts: 3

  alias RestaurantDash.Tenancy
  alias RestaurantDash.Integrations.Clover

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    restaurant_id = Map.get(args, "restaurant_id")

    restaurants =
      if restaurant_id do
        case Tenancy.get_restaurant(restaurant_id) do
          nil -> []
          r -> [r]
        end
      else
        Tenancy.list_active_restaurants()
        |> Enum.filter(&Clover.connected?/1)
      end

    results =
      Enum.map(restaurants, fn restaurant ->
        if not Clover.connected?(restaurant) do
          # Skip gracefully — restaurant lost Clover connection
          {:skipped, restaurant.id}
        else
          case Clover.sync_inventory(restaurant) do
            {:ok, result} ->
              Logger.info(
                "[CloverInventorySync] Restaurant #{restaurant.id}: " <>
                  "updated=#{result.updated}, skipped=#{result.skipped}"
              )

              {:ok, restaurant.id, result}

            {:error, reason} ->
              Logger.error(
                "[CloverInventorySync] Restaurant #{restaurant.id} failed: #{inspect(reason)}"
              )

              {:error, restaurant.id, reason}
          end
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if errors == [] do
      :ok
    else
      {:error, "#{length(errors)} restaurant(s) failed inventory sync"}
    end
  end

  @doc "Enqueue a sync for a specific restaurant (manual 'Sync Now')."
  def enqueue_for(restaurant_id) do
    %{"restaurant_id" => restaurant_id}
    |> new()
    |> Oban.insert()
  end

  @doc "Enqueue a global sync across all connected restaurants."
  def enqueue_global do
    %{}
    |> new()
    |> Oban.insert()
  end
end
