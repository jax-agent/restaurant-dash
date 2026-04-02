defmodule RestaurantDashWeb.NotificationBellLive do
  @moduledoc """
  Live component: notification bell icon with unread count badge.

  Shows in the dashboard header. Clicking opens a dropdown with recent
  in-app notifications. Real-time updates via PubSub.

  Usage:
    <.live_component module={NotificationBellLive} id="notification-bell"
      restaurant_id={@current_scope.restaurant_id} user_id={@current_scope.user.id} />
  """
  use RestaurantDashWeb, :live_component

  alias RestaurantDash.Notifications.InApp

  @max_notifications 20

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:notifications, [])
     |> assign(:unread_count, 0)
     |> assign(:open, false)}
  end

  @impl true
  def update(%{restaurant_id: restaurant_id, user_id: user_id} = assigns, socket) do
    if connected?(socket) do
      InApp.subscribe(user_id)
    end

    notifications = InApp.list_for_restaurant(restaurant_id, @max_notifications)
    unread = InApp.unread_count(restaurant_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread)}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, update(socket, :open, &(!&1))}
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    InApp.mark_all_read(socket.assigns.restaurant_id)

    notifications =
      InApp.list_for_restaurant(socket.assigns.restaurant_id, @max_notifications)

    {:noreply,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, 0)}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    InApp.mark_read(String.to_integer(id))
    unread = InApp.unread_count(socket.assigns.restaurant_id)

    notifications =
      socket.assigns.notifications
      |> Enum.map(fn n ->
        if n.id == String.to_integer(id) do
          %{n | status: "sent"}
        else
          n
        end
      end)

    {:noreply,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread)}
  end

  # LiveComponents receive PubSub messages via handle_info in the parent LiveView
  # or via the send_update mechanism. We implement update/2 to handle external pushes.
  def handle_info({:new_notification, notification}, socket) do
    notifications = [notification | socket.assigns.notifications] |> Enum.take(@max_notifications)
    unread = socket.assigns.unread_count + 1

    {:noreply,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative" id={"notification-bell-#{@id}"}>
      <%!-- Bell Button --%>
      <button
        phx-click="toggle"
        phx-target={@myself}
        class="relative p-2 rounded-full hover:bg-white/10 transition-colors"
        aria-label="Notifications"
      >
        <.icon name="hero-bell" class="w-6 h-6 text-white" />
        <%= if @unread_count > 0 do %>
          <span class="absolute -top-1 -right-1 min-w-5 h-5 bg-red-500 text-white text-xs font-bold rounded-full flex items-center justify-center px-1">
            {if @unread_count > 99, do: "99+", else: @unread_count}
          </span>
        <% end %>
      </button>

      <%!-- Dropdown --%>
      <%= if @open do %>
        <%!-- Backdrop --%>
        <div
          phx-click="close"
          phx-target={@myself}
          class="fixed inset-0 z-40"
        />

        <%!-- Panel --%>
        <div class="absolute right-0 top-full mt-2 w-80 bg-white rounded-2xl shadow-2xl border border-gray-100 z-50 overflow-hidden">
          <%!-- Header --%>
          <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">
            <h3 class="font-semibold text-gray-900 text-sm">Notifications</h3>
            <%= if @unread_count > 0 do %>
              <button
                phx-click="mark_all_read"
                phx-target={@myself}
                class="text-xs text-blue-600 hover:text-blue-700 font-medium"
              >
                Mark all read
              </button>
            <% end %>
          </div>

          <%!-- Notification List --%>
          <div class="max-h-96 overflow-y-auto divide-y divide-gray-50">
            <%= if @notifications == [] do %>
              <div class="px-4 py-8 text-center">
                <p class="text-2xl mb-2">🔔</p>
                <p class="text-sm text-gray-500">No notifications yet</p>
              </div>
            <% else %>
              <%= for notif <- @notifications do %>
                <div
                  class={"px-4 py-3 flex items-start gap-3 hover:bg-gray-50 cursor-default #{if notif.status == "pending", do: "bg-blue-50/40", else: ""}"}
                  phx-click="mark_read"
                  phx-value-id={notif.id}
                  phx-target={@myself}
                >
                  <div class="flex-shrink-0 mt-0.5">
                    <span class="text-lg">{notification_icon(notif.template)}</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm text-gray-800 leading-snug">{notif.body}</p>
                    <p class="text-xs text-gray-400 mt-1">{format_time(notif.inserted_at)}</p>
                  </div>
                  <%= if notif.status == "pending" do %>
                    <div class="flex-shrink-0 mt-1.5">
                      <div class="w-2 h-2 rounded-full bg-blue-500" />
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp notification_icon("in_app:new_order"), do: "🛒"
  defp notification_icon("in_app:driver_assigned"), do: "🚗"
  defp notification_icon("in_app:payment_received"), do: "💳"
  defp notification_icon("in_app:low_rating_alert"), do: "⭐"
  defp notification_icon("in_app:delivery_assigned"), do: "📦"
  defp notification_icon("in_app:delivery_cancelled"), do: "❌"
  defp notification_icon(_), do: "🔔"

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end
end
