defmodule RestaurantDash.Workers.SquareInventorySyncWorker do
  @moduledoc """
  Oban worker that periodically syncs item availability from Square.

  Uses Square's BatchRetrieveInventoryCounts API.
  When items reach 0 quantity → mark unavailable in our menu.
  When quantity > 0 → restore availability.

  Default interval: every 5 minutes (configured in Oban cron queue).
  Supports manual "Sync Now" via enqueue_for/1.
  """

  use Oban.Worker,
    queue: :square,
    max_attempts: 3

  alias RestaurantDash.Tenancy
  alias RestaurantDash.Integrations.Square

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
        |> Enum.filter(&Square.connected?/1)
      end

    results =
      Enum.map(restaurants, fn restaurant ->
        if not Square.connected?(restaurant) do
          {:skipped, restaurant.id}
        else
          case Square.sync_inventory(restaurant) do
            {:ok, result} ->
              Logger.info(
                "[SquareInventorySync] Restaurant #{restaurant.id}: " <>
                  "updated=#{result.updated}, skipped=#{result.skipped}"
              )

              {:ok, restaurant.id, result}

            {:error, reason} ->
              Logger.error(
                "[SquareInventorySync] Restaurant #{restaurant.id} failed: #{inspect(reason)}"
              )

              {:error, restaurant.id, reason}
          end
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if errors == [] do
      :ok
    else
      {:error, "#{length(errors)} restaurant(s) failed Square inventory sync"}
    end
  end

  @doc "Enqueue a sync for a specific restaurant (manual 'Sync Now')."
  def enqueue_for(restaurant_id) do
    %{"restaurant_id" => restaurant_id}
    |> new()
    |> Oban.insert()
  end

  @doc "Enqueue a global sync across all Square-connected restaurants."
  def enqueue_global do
    %{}
    |> new()
    |> Oban.insert()
  end
end
