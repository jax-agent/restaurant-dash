defmodule RestaurantDash.Workers.EmailNotificationWorker do
  @moduledoc """
  Oban worker for async email notification sending.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3

  alias RestaurantDash.{Orders, Tenancy, Notifications}
  alias RestaurantDash.Notifications.{Email, Templates}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "order_id" => order_id,
          "restaurant_id" => restaurant_id,
          "template" => template
        }
      }) do
    order = Orders.get_order_with_items(order_id)
    restaurant = restaurant_id && Tenancy.get_restaurant(restaurant_id)

    if is_nil(order) or is_nil(order.customer_email) do
      :ok
    else
      send_email(order, restaurant, template)
    end
  end

  @doc "Enqueue an email notification."
  def enqueue(order_id, restaurant_id, template) do
    %{
      "order_id" => order_id,
      "restaurant_id" => restaurant_id,
      "template" => template
    }
    |> new()
    |> Oban.insert()
  end

  # ─── Private ─────────────────────────────────────────────────────────────

  defp send_email(order, restaurant, template) do
    email =
      case template do
        "email:order_confirmed" ->
          Email.order_confirmed(order, restaurant)

        "email:delivery_update" ->
          status_label = status_label(order.status)
          Email.delivery_update(order, restaurant, status_label)

        _ ->
          # Fallback: build a simple notification from template
          vars = build_vars(order, restaurant)
          {:ok, subject} = Templates.render(template, vars)
          Email.delivery_update(order, restaurant, subject)
      end

    # Record the notification
    {:ok, notification} =
      Notifications.create_notification(%{
        restaurant_id: order.restaurant_id,
        order_id: order.id,
        recipient_type: "customer",
        recipient_contact: order.customer_email,
        channel: "email",
        template: template,
        body: email.text_body || email.html_body || ""
      })

    case Email.deliver(email) do
      {:ok, _} ->
        Notifications.mark_sent(notification)
        :ok

      {:error, reason} ->
        Notifications.mark_failed(notification, inspect(reason))
        {:error, reason}
    end
  end

  defp status_label("preparing"), do: "Your order is being prepared"
  defp status_label("out_for_delivery"), do: "Your order is on the way!"
  defp status_label("delivered"), do: "Your order has been delivered"
  defp status_label(status), do: String.replace(status, "_", " ") |> String.capitalize()

  defp build_vars(order, restaurant) do
    %{
      "customer_name" => order.customer_name || "Customer",
      "order_number" => to_string(order.id),
      "restaurant_name" => (restaurant && restaurant.name) || "Restaurant"
    }
  end
end
