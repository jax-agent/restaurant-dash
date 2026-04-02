defmodule RestaurantDashWeb.NotificationSettingsLive do
  @moduledoc """
  Restaurant notification alert settings page.
  Owners can configure which alerts they receive and via which channels.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Tenancy, Notifications.Preferences}

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        prefs = Preferences.get(restaurant)

        {:ok,
         socket
         |> assign(:current_user, current_user)
         |> assign(:restaurant, restaurant)
         |> assign(:preferences, prefs)
         |> assign(:saved, false)}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Access denied.")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("toggle", %{"alert" => alert_type, "channel" => channel}, socket) do
    case Preferences.toggle(socket.assigns.restaurant, alert_type, channel) do
      {:ok, updated_restaurant} ->
        prefs = Preferences.get(updated_restaurant)

        {:noreply,
         socket
         |> assign(:restaurant, updated_restaurant)
         |> assign(:preferences, prefs)
         |> assign(:saved, true)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save preferences.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%!-- Header --%>
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-3xl mx-auto flex items-center justify-between">
          <div>
            <h1 class="text-lg font-bold text-gray-900">Notification Settings</h1>
            <p class="text-sm text-gray-500">{@restaurant.name}</p>
          </div>
          <a href="/dashboard/settings" class="text-sm text-blue-600 hover:underline">
            ← Back to Settings
          </a>
        </div>
      </header>

      <main class="max-w-3xl mx-auto px-6 py-8">
        <%= if @saved do %>
          <div class="mb-6 rounded-xl bg-green-50 border border-green-200 px-4 py-3 text-sm text-green-700 flex items-center gap-2">
            ✓ Preferences saved
          </div>
        <% end %>

        <div class="bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden">
          <%!-- Table header --%>
          <div class="px-6 py-4 border-b border-gray-100 bg-gray-50">
            <div class="grid grid-cols-4 gap-4 items-center">
              <div class="col-span-1 text-sm font-semibold text-gray-600">Alert Type</div>
              <%= for channel <- Preferences.channels() do %>
                <div class="text-center text-sm font-semibold text-gray-600">
                  {Preferences.channel_label(channel)}
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Alert rows --%>
          <div class="divide-y divide-gray-100">
            <%= for alert_type <- Preferences.alert_types() do %>
              <div class="px-6 py-4">
                <div class="grid grid-cols-4 gap-4 items-center">
                  <div class="col-span-1">
                    <p class="text-sm font-medium text-gray-900">
                      {Preferences.label(alert_type)}
                    </p>
                    <p class="text-xs text-gray-400 mt-0.5">
                      {alert_description(alert_type)}
                    </p>
                  </div>

                  <%= for channel <- Preferences.channels() do %>
                    <div class="flex justify-center">
                      <button
                        phx-click="toggle"
                        phx-value-alert={alert_type}
                        phx-value-channel={channel}
                        class={toggle_class(get_in(@preferences, [alert_type, channel]))}
                        role="switch"
                        aria-checked={to_string(get_in(@preferences, [alert_type, channel]) == true)}
                      >
                        <span class={toggle_knob_class(get_in(@preferences, [alert_type, channel]))} />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <p class="mt-4 text-xs text-gray-400 text-center">
          Changes take effect immediately
        </p>
      </main>
    </div>
    """
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  defp alert_description("new_order"), do: "When a customer places an order"
  defp alert_description("payment_alert"), do: "When a payment is received or fails"
  defp alert_description("low_stock_alert"), do: "When menu items are running low"
  defp alert_description("driver_alert"), do: "Driver assignment and delivery updates"
  defp alert_description(_), do: ""

  defp toggle_class(true) do
    "relative inline-flex h-6 w-11 items-center rounded-full bg-blue-600 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
  end

  defp toggle_class(_) do
    "relative inline-flex h-6 w-11 items-center rounded-full bg-gray-200 transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
  end

  defp toggle_knob_class(true) do
    "inline-block h-4 w-4 translate-x-6 transform rounded-full bg-white transition-transform shadow"
  end

  defp toggle_knob_class(_) do
    "inline-block h-4 w-4 translate-x-1 transform rounded-full bg-white transition-transform shadow"
  end

  defp get_current_user(socket) do
    case socket.assigns do
      %{current_scope: %{user: user}} -> user
      %{current_user: user} -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

  defp authorize(user) do
    case user.role do
      role when role in ["owner", "staff"] ->
        case Tenancy.get_restaurant(user.restaurant_id) do
          nil -> {:error, :unauthorized}
          restaurant -> {:ok, restaurant}
        end

      _ ->
        {:error, :unauthorized}
    end
  end
end
