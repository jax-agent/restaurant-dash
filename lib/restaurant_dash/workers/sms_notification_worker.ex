defmodule RestaurantDash.Workers.SMSNotificationWorker do
  @moduledoc """
  Oban worker for async SMS notification sending.

  Loads the order, builds the SMS body from the template, sends via Twilio,
  and records the notification with sent/failed status.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias RestaurantDash.{Orders, Tenancy, Notifications}
  alias RestaurantDash.Notifications.{SMS, Templates}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "order_id" => order_id,
          "restaurant_id" => restaurant_id,
          "template" => template,
          "recipient" => recipient
        }
      }) do
    order = Orders.get_order(order_id)
    restaurant = restaurant_id && Tenancy.get_restaurant(restaurant_id)

    if is_nil(order) do
      # Order deleted — nothing to do
      :ok
    else
      phone = resolve_phone(order, recipient)

      if is_nil(phone) do
        :ok
      else
        vars = build_vars(order, restaurant)
        send_sms(order, restaurant, template, phone, recipient, vars)
      end
    end
  end

  # ─── Enqueue Helpers ────────────────────────────────────────────────────

  @doc "Enqueue an SMS to the order's customer."
  def enqueue(order_id, restaurant_id, template) do
    %{
      "order_id" => order_id,
      "restaurant_id" => restaurant_id,
      "template" => template,
      "recipient" => "customer"
    }
    |> new()
    |> Oban.insert()
  end

  @doc "Enqueue an SMS to the assigned driver."
  def enqueue_driver(order_id, restaurant_id, template) do
    %{
      "order_id" => order_id,
      "restaurant_id" => restaurant_id,
      "template" => template,
      "recipient" => "driver"
    }
    |> new()
    |> Oban.insert()
  end

  # ─── Private ────────────────────────────────────────────────────────────

  defp resolve_phone(order, "customer"), do: order.customer_phone

  defp resolve_phone(order, "driver") when not is_nil(order.driver_id) do
    case RestaurantDash.Repo.get(RestaurantDash.Accounts.User, order.driver_id) do
      nil -> nil
      user -> Map.get(user, :phone)
    end
  end

  defp resolve_phone(_order, _), do: nil

  defp send_sms(order, _restaurant, template, phone, recipient_type, vars) do
    case Templates.render(template, vars) do
      {:ok, body} ->
        # Create the notification record (marks as pending)
        {:ok, notification} =
          Notifications.create_notification(%{
            restaurant_id: order.restaurant_id,
            order_id: order.id,
            recipient_type: recipient_type,
            recipient_contact: phone,
            channel: "sms",
            template: template,
            body: body
          })

        # Send via Twilio (or mock)
        case SMS.send(phone, body) do
          {:ok, _sid} ->
            Notifications.mark_sent(notification)
            :ok

          {:error, reason} ->
            Notifications.mark_failed(notification, reason)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_vars(order, restaurant) do
    tracking_url = tracking_url(order)
    restaurant_name = (restaurant && restaurant.name) || "Restaurant"

    %{
      "customer_name" => order.customer_name || "Customer",
      "order_number" => to_string(order.id),
      "restaurant_name" => restaurant_name,
      "eta" => "30-45 min",
      "tracking_url" => tracking_url,
      "delivery_address" => order.delivery_address || "",
      "driver_name" => driver_name(order)
    }
  end

  defp tracking_url(order) do
    base =
      Application.get_env(:restaurant_dash, RestaurantDashWeb.Endpoint)[:url][:host] ||
        "localhost"

    "https://#{base}/orders/#{order.id}/track"
  end

  defp driver_name(%{driver_id: nil}), do: "Driver"

  defp driver_name(%{driver_id: driver_id}) when not is_nil(driver_id) do
    case RestaurantDash.Repo.get(RestaurantDash.Accounts.User, driver_id) do
      nil -> "Driver"
      user -> user.email |> String.split("@") |> hd() |> String.capitalize()
    end
  end
end
