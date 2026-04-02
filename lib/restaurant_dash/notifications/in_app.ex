defmodule RestaurantDash.Notifications.InApp do
  @moduledoc """
  In-app notification system for owners, staff, and drivers.

  Stores notifications in the DB and broadcasts via PubSub.
  Users subscribe to "notifications:{user_id}" to receive real-time events.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Notifications
  alias RestaurantDash.Notifications.Notification

  @pubsub RestaurantDash.PubSub

  # ─── PubSub ──────────────────────────────────────────────────────────────

  @doc "Subscribe to in-app notifications for a user."
  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(@pubsub, "notifications:#{user_id}")
  end

  @doc "Broadcast a notification to a user."
  def broadcast(user_id, notification) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "notifications:#{user_id}",
      {:new_notification, notification}
    )
  end

  # ─── Notification Feed ────────────────────────────────────────────────────

  @doc """
  List recent in-app notifications for a restaurant (owner/staff dashboard).
  """
  def list_for_restaurant(restaurant_id, limit \\ 20) do
    Notification
    |> where([n], n.restaurant_id == ^restaurant_id and n.channel == "in_app")
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Count unread (pending) in-app notifications for a restaurant."
  def unread_count(restaurant_id) do
    Notification
    |> where(
      [n],
      n.restaurant_id == ^restaurant_id and n.channel == "in_app" and n.status == "pending"
    )
    |> Repo.aggregate(:count, :id)
  end

  @doc "Mark all in-app notifications as read (sent) for a restaurant."
  def mark_all_read(restaurant_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Notification
    |> where(
      [n],
      n.restaurant_id == ^restaurant_id and n.channel == "in_app" and n.status == "pending"
    )
    |> Repo.update_all(set: [status: "sent", sent_at: now])
  end

  @doc "Mark a single notification as read."
  def mark_read(notification_id) do
    case Repo.get(Notification, notification_id) do
      nil -> {:error, :not_found}
      notification -> Notifications.mark_sent(notification)
    end
  end

  # ─── Create & Broadcast ───────────────────────────────────────────────────

  @doc """
  Create an in-app notification and broadcast it to relevant users.
  """
  def create_and_broadcast(attrs, user_ids \\ []) do
    attrs_with_channel = Map.put(attrs, :channel, "in_app")

    case Notifications.create_notification(attrs_with_channel) do
      {:ok, notification} ->
        # Broadcast to all relevant user IDs
        Enum.each(user_ids, fn user_id ->
          broadcast(user_id, notification)
        end)

        {:ok, notification}

      error ->
        error
    end
  end
end
