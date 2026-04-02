defmodule RestaurantDash.Notifications do
  @moduledoc """
  The Notifications context.

  Manages creating, queuing, and tracking notifications across all channels
  (SMS, email, push, in_app).
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Notifications.Notification
  alias RestaurantDash.Notifications.Templates

  @pubsub RestaurantDash.PubSub

  # ─── PubSub ──────────────────────────────────────────────────────────────

  @doc "Subscribe to in-app notification events for a given user."
  def subscribe_user(user_id) do
    Phoenix.PubSub.subscribe(@pubsub, "notifications:#{user_id}")
  end

  @doc "Broadcast a new in-app notification to a user."
  def broadcast_to_user(user_id, notification) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "notifications:#{user_id}",
      {:new_notification, notification}
    )
  end

  # ─── CRUD ────────────────────────────────────────────────────────────────

  @doc "Create a notification record."
  def create_notification(attrs) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Mark a notification as sent."
  def mark_sent(%Notification{} = notification) do
    notification
    |> Notification.sent_changeset()
    |> Repo.update()
  end

  @doc "Mark a notification as failed with an error message."
  def mark_failed(%Notification{} = notification, error_message) do
    notification
    |> Notification.failed_changeset(error_message)
    |> Repo.update()
  end

  @doc "Get a single notification by ID."
  def get_notification!(id), do: Repo.get!(Notification, id)

  @doc "List all notifications for a restaurant."
  def list_notifications(restaurant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    channel = Keyword.get(opts, :channel)
    status = Keyword.get(opts, :status)

    Notification
    |> where([n], n.restaurant_id == ^restaurant_id)
    |> maybe_filter_channel(channel)
    |> maybe_filter_status(status)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "List notifications for an order."
  def list_notifications_for_order(order_id) do
    Notification
    |> where([n], n.order_id == ^order_id)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  @doc "Count pending notifications."
  def count_pending(restaurant_id) do
    Notification
    |> where([n], n.restaurant_id == ^restaurant_id and n.status == "pending")
    |> Repo.aggregate(:count, :id)
  end

  # ─── Template Helpers ────────────────────────────────────────────────────

  @doc """
  Build and persist a notification from a template.
  Returns {:ok, notification} or {:error, reason}.
  """
  def create_from_template(template_key, vars, attrs) do
    case Templates.render(template_key, vars) do
      {:ok, body} ->
        notification_attrs =
          attrs
          |> Map.put(:template, template_key)
          |> Map.put(:body, body)

        create_notification(notification_attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ─── Order Lifecycle Notifications ───────────────────────────────────────

  @doc """
  Send all appropriate notifications for an order status change.
  This is the main entry point — queues async Oban jobs.
  """
  def notify_order_status_change(order, status, opts \\ []) do
    restaurant = opts[:restaurant] || load_restaurant(order)

    case status do
      "new" ->
        maybe_queue_sms(order, restaurant, "sms:order_confirmed")
        maybe_queue_email(order, restaurant, "email:order_confirmed")
        maybe_queue_in_app_owner(order, restaurant, "in_app:new_order")

      "preparing" ->
        maybe_queue_sms(order, restaurant, "sms:order_preparing")

      "assigned" ->
        maybe_queue_in_app_owner(order, restaurant, "in_app:driver_assigned")
        maybe_queue_driver_sms(order, restaurant, "sms:driver_assigned")

      "out_for_delivery" ->
        maybe_queue_sms(order, restaurant, "sms:out_for_delivery")

      "delivered" ->
        maybe_queue_sms(order, restaurant, "sms:delivered")
        maybe_queue_in_app_owner(order, restaurant, "in_app:payment_received")

      _ ->
        :ok
    end
  end

  # ─── Rate Limiting ───────────────────────────────────────────────────────

  @doc """
  Check if a notification for this order+channel+template was already sent.
  Enforces max 1 notification per order per status/template.
  """
  def already_notified?(order_id, template) do
    Notification
    |> where([n], n.order_id == ^order_id and n.template == ^template)
    |> where([n], n.status in ["sent", "pending"])
    |> Repo.exists?()
  end

  # ─── Private ─────────────────────────────────────────────────────────────

  defp maybe_queue_sms(order, restaurant, template) do
    contact = order.customer_phone

    if contact && not already_notified?(order.id, template) do
      alias RestaurantDash.Workers.SMSNotificationWorker
      SMSNotificationWorker.enqueue(order.id, restaurant && restaurant.id, template)
    end
  end

  defp maybe_queue_driver_sms(order, restaurant, template) do
    if order.driver_id && not already_notified?(order.id, template) do
      alias RestaurantDash.Workers.SMSNotificationWorker
      SMSNotificationWorker.enqueue_driver(order.id, restaurant && restaurant.id, template)
    end
  end

  defp maybe_queue_email(order, restaurant, template) do
    contact = order.customer_email

    if contact && not already_notified?(order.id, template) do
      alias RestaurantDash.Workers.EmailNotificationWorker
      EmailNotificationWorker.enqueue(order.id, restaurant && restaurant.id, template)
    end
  end

  defp maybe_queue_in_app_owner(order, restaurant, template) do
    if restaurant do
      alias RestaurantDash.Workers.InAppNotificationWorker
      InAppNotificationWorker.enqueue_for_restaurant(order.id, restaurant.id, template)
    end
  end

  defp load_restaurant(%{restaurant_id: nil}), do: nil

  defp load_restaurant(%{restaurant_id: restaurant_id}) do
    RestaurantDash.Tenancy.get_restaurant(restaurant_id)
  end

  defp maybe_filter_channel(query, nil), do: query
  defp maybe_filter_channel(query, channel), do: where(query, [n], n.channel == ^channel)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [n], n.status == ^status)
end
