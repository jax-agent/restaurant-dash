defmodule RestaurantDash.Workers.InAppNotificationWorker do
  @moduledoc """
  Oban worker for creating in-app notifications for restaurant owners/staff.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3

  alias RestaurantDash.{Orders, Tenancy}
  alias RestaurantDash.Notifications.{InApp, Templates}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "order_id" => order_id,
          "restaurant_id" => restaurant_id,
          "template" => template
        }
      }) do
    order = Orders.get_order(order_id)
    restaurant = Tenancy.get_restaurant(restaurant_id)

    if is_nil(order) or is_nil(restaurant) do
      :ok
    else
      vars = build_vars(order, restaurant)

      case Templates.render(template, vars) do
        {:ok, body} ->
          attrs = %{
            restaurant_id: restaurant_id,
            order_id: order_id,
            recipient_type: "owner",
            recipient_contact: "in_app",
            channel: "in_app",
            template: template,
            body: body
          }

          # Find owner user IDs for this restaurant to broadcast to
          owner_ids = Tenancy.list_owner_user_ids(restaurant_id)
          InApp.create_and_broadcast(attrs, owner_ids)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Enqueue an in-app notification for a restaurant's owners."
  def enqueue_for_restaurant(order_id, restaurant_id, template) do
    %{
      "order_id" => order_id,
      "restaurant_id" => restaurant_id,
      "template" => template
    }
    |> new()
    |> Oban.insert()
  end

  # ─── Private ─────────────────────────────────────────────────────────────

  defp build_vars(order, restaurant) do
    total = format_price(order.total_amount)

    %{
      "order_number" => to_string(order.id),
      "restaurant_name" => restaurant.name,
      "total" => total,
      "driver_name" => "Driver",
      "rating" => to_string(order.driver_rating || 0)
    }
  end

  defp format_price(nil), do: "$0.00"
  defp format_price(0), do: "$0.00"

  defp format_price(cents) do
    "$#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end
end
