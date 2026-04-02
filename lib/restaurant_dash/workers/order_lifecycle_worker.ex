defmodule RestaurantDash.Workers.OrderLifecycleWorker do
  @moduledoc """
  Transitions an order through its lifecycle:
    new → preparing (after 2 minutes)
    preparing → out_for_delivery (after 3 minutes)
    out_for_delivery → delivered (after 5 minutes)
  """

  use Oban.Worker,
    queue: :orders,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  alias RestaurantDash.Orders

  # Transition delays in seconds
  @transitions %{
    "new" => {"preparing", 2 * 60},
    "preparing" => {"out_for_delivery", 3 * 60},
    "out_for_delivery" => {"delivered", 5 * 60}
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id, "from_status" => from_status}}) do
    case Orders.get_order(order_id) do
      nil ->
        # Order was deleted — nothing to do
        :ok

      order ->
        if order.status == from_status do
          {to_status, _delay} = @transitions[from_status]
          {:ok, updated_order} = Orders.transition_order(order, to_status)

          # Schedule the next transition if one exists
          maybe_schedule_next(updated_order)
        end

        :ok
    end
  end

  @doc """
  Schedule the first lifecycle transition for a newly created order.
  """
  def schedule_for(%{id: order_id, status: "new"}) do
    {"preparing", delay} = @transitions["new"]

    %{"order_id" => order_id, "from_status" => "new"}
    |> new(schedule_in: delay)
    |> Oban.insert()
  end

  def schedule_for(_order), do: {:ok, nil}

  # ─── Private ───────────────────────────────────────────────────────────────

  defp maybe_schedule_next(%{status: status, id: order_id}) do
    case Map.get(@transitions, status) do
      {_next_status, delay} ->
        %{"order_id" => order_id, "from_status" => status}
        |> new(schedule_in: delay)
        |> Oban.insert()

      nil ->
        :ok
    end
  end
end
