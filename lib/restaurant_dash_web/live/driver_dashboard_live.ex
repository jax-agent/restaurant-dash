defmodule RestaurantDashWeb.DriverDashboardLive do
  @moduledoc """
  Driver mobile dashboard. Mobile-optimized LiveView for drivers.

  Shows:
  - Current delivery (or "Waiting for orders")
  - Status buttons: Picked Up → Delivered
  - Availability toggle in header
  - Delivery history (recent completed)
  - Earnings summary (today's count + tips)

  Requires driver role.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Drivers, Orders}

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, profile} ->
        if connected?(socket) do
          Drivers.subscribe_driver(current_user.id)
          Orders.subscribe()
        end

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:profile, profile)
          |> assign(:page_title, "Driver Dashboard")
          |> load_driver_data(profile, current_user.id)

        {:ok, socket}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :no_profile} ->
        {:ok,
         socket
         |> put_flash(:error, "Driver profile not found. Please complete registration.")
         |> redirect(to: ~p"/drivers/signup")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Driver access only.")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("toggle_availability", _params, socket) do
    profile = socket.assigns.profile

    new_status =
      case profile.status do
        "available" -> "offline"
        _ -> "available"
      end

    case Drivers.set_status(profile, new_status) do
      {:ok, updated_profile} ->
        {:noreply,
         socket
         |> assign(:profile, updated_profile)
         |> put_flash(:info, "Status updated to #{new_status}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def handle_event("mark_picked_up", _params, socket) do
    case socket.assigns[:active_delivery] do
      nil ->
        {:noreply, put_flash(socket, :error, "No active delivery.")}

      order ->
        case Orders.update_delivery_status(order, "picked_up") do
          {:ok, updated_order} ->
            {:noreply,
             socket
             |> assign(:active_delivery, updated_order)
             |> put_flash(:info, "Marked as picked up!")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update status.")}
        end
    end
  end

  @impl true
  def handle_event("mark_delivered", _params, socket) do
    case socket.assigns[:active_delivery] do
      nil ->
        {:noreply, put_flash(socket, :error, "No active delivery.")}

      order ->
        user_id = socket.assigns.current_user.id
        profile = socket.assigns.profile

        with {:ok, _order} <- Orders.update_delivery_status(order, "delivered"),
             {:ok, updated_profile} <- Drivers.set_status(profile, "available") do
          socket =
            socket
            |> assign(:profile, updated_profile)
            |> put_flash(:info, "Delivery complete! 🎉")
            |> load_driver_data(updated_profile, user_id)

          {:noreply, socket}
        else
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, to_string(reason))}
        end
    end
  end

  @impl true
  def handle_info({:driver_updated, profile}, socket) do
    if profile.user_id == socket.assigns.current_user.id do
      {:noreply,
       socket
       |> assign(:profile, profile)
       |> load_driver_data(profile, socket.assigns.current_user.id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:order_updated, order}, socket) do
    user_id = socket.assigns.current_user.id

    if order.driver_id == user_id do
      {:noreply, load_driver_data(socket, socket.assigns.profile, user_id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:order_created, _order}, socket), do: {:noreply, socket}
  def handle_info({:order_position_updated, _order}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100">
      <!-- Mobile header with availability toggle -->
      <div class="bg-white shadow-sm sticky top-0 z-10">
        <div class="max-w-lg mx-auto px-4 py-3 flex items-center justify-between">
          <div>
            <h1 class="text-lg font-bold text-gray-900">Driver Dashboard</h1>
            <p class="text-xs text-gray-500">{@current_user.name || @current_user.email}</p>
          </div>
          <div class="flex items-center gap-3">
            <span class={"text-sm font-medium #{status_text_color(@profile.status)}"}>
              {status_label(@profile.status)}
            </span>
            <button
              phx-click="toggle_availability"
              class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none #{toggle_bg(@profile.status)}"}
            >
              <span class={"pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{toggle_translate(@profile.status)}"}>
              </span>
            </button>
          </div>
        </div>
      </div>

      <div class="max-w-lg mx-auto px-4 py-6 space-y-6">
        <!-- Approval notice -->
        <%= unless @profile.is_approved do %>
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
            <div class="flex items-center gap-2">
              <span class="text-yellow-600 font-bold">⏳</span>
              <div>
                <p class="font-medium text-yellow-800">Account Pending Approval</p>
                <p class="text-sm text-yellow-700 mt-1">
                  Your account is being reviewed by the restaurant owner. You'll be notified when approved.
                </p>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Current delivery -->
        <div class="bg-white rounded-xl shadow-sm overflow-hidden">
          <div class="px-4 py-3 border-b border-gray-100 bg-gray-50">
            <h2 class="font-semibold text-gray-700 text-sm uppercase tracking-wide">
              Current Delivery
            </h2>
          </div>

          <%= if @active_delivery do %>
            <div class="p-4">
              <div class="flex items-start justify-between mb-3">
                <div>
                  <p class="font-semibold text-gray-900">{@active_delivery.customer_name}</p>
                  <p class="text-sm text-gray-500">Order #{@active_delivery.id}</p>
                </div>
                <span class={"px-2 py-1 text-xs font-semibold rounded-full #{delivery_status_color(@active_delivery.status)}"}>
                  {format_status(@active_delivery.status)}
                </span>
              </div>

              <div class="bg-gray-50 rounded-lg p-3 mb-3">
                <p class="text-sm font-medium text-gray-700 mb-1">📍 Delivery Address</p>
                <p class="text-sm text-gray-900">{@active_delivery.delivery_address}</p>
                <a
                  href={"https://www.google.com/maps/dir/?api=1&destination=#{URI.encode(@active_delivery.delivery_address || "")}"}
                  target="_blank"
                  class="inline-flex items-center mt-2 text-xs text-indigo-600 hover:text-indigo-800"
                >
                  🗺️ Open in Google Maps →
                </a>
              </div>

              <%= if @active_delivery.order_items && length(@active_delivery.order_items) > 0 do %>
                <div class="mb-4">
                  <p class="text-sm font-medium text-gray-700 mb-1">📦 Items</p>
                  <ul class="space-y-1">
                    <%= for item <- @active_delivery.order_items do %>
                      <li class="text-sm text-gray-600">
                        {item.quantity}x {item.name}
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
              
    <!-- Action buttons -->
              <div class="flex gap-3">
                <%= if @active_delivery.status == "assigned" do %>
                  <button
                    phx-click="mark_picked_up"
                    class="flex-1 py-3 px-4 bg-orange-500 hover:bg-orange-600 text-white font-semibold rounded-lg transition-colors"
                  >
                    ✅ Picked Up
                  </button>
                <% end %>
                <%= if @active_delivery.status == "picked_up" do %>
                  <button
                    phx-click="mark_delivered"
                    class="flex-1 py-3 px-4 bg-green-500 hover:bg-green-600 text-white font-semibold rounded-lg transition-colors"
                  >
                    🏠 Mark Delivered
                  </button>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="p-8 text-center">
              <%= if @profile.status == "available" do %>
                <p class="text-4xl mb-2">⏳</p>
                <p class="font-medium text-gray-700">Waiting for orders...</p>
                <p class="text-sm text-gray-500 mt-1">
                  You're online and ready to receive deliveries.
                </p>
              <% else %>
                <p class="text-4xl mb-2">😴</p>
                <p class="font-medium text-gray-500">You're offline</p>
                <p class="text-sm text-gray-400 mt-1">
                  Toggle availability above to start receiving orders.
                </p>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Today's earnings -->
        <div class="grid grid-cols-2 gap-4">
          <div class="bg-white rounded-xl shadow-sm p-4">
            <p class="text-3xl font-bold text-gray-900">{@today_count}</p>
            <p class="text-sm text-gray-500 mt-1">Deliveries today</p>
          </div>
          <div class="bg-white rounded-xl shadow-sm p-4">
            <p class="text-3xl font-bold text-green-600">
              ${format_cents(@today_tips)}
            </p>
            <p class="text-sm text-gray-500 mt-1">Tips today</p>
          </div>
        </div>
        
    <!-- Recent delivery history -->
        <div class="bg-white rounded-xl shadow-sm overflow-hidden">
          <div class="px-4 py-3 border-b border-gray-100 bg-gray-50">
            <h2 class="font-semibold text-gray-700 text-sm uppercase tracking-wide">
              Recent Deliveries
            </h2>
          </div>

          <%= if @recent_deliveries == [] do %>
            <div class="p-6 text-center text-gray-400 text-sm">
              No deliveries yet
            </div>
          <% else %>
            <ul class="divide-y divide-gray-100">
              <%= for order <- @recent_deliveries do %>
                <li class="px-4 py-3 flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-gray-900">{order.customer_name}</p>
                    <p class="text-xs text-gray-500">{format_time(order.delivered_at)}</p>
                  </div>
                  <div class="text-right">
                    <p class="text-sm font-semibold text-green-600">
                      ${format_cents(order.tip_amount || 0)} tip
                    </p>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ─── Private ───────────────────────────────────────────────────────────────

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

  defp authorize(%{role: "driver"} = user) do
    case Drivers.get_profile_by_user_id(user.id) do
      nil -> {:error, :no_profile}
      profile -> {:ok, profile}
    end
  end

  defp authorize(_), do: {:error, :unauthorized}

  defp load_driver_data(socket, profile, user_id) do
    active_delivery = Orders.get_active_delivery(user_id)

    recent_deliveries =
      Orders.list_driver_orders(user_id)
      |> Enum.filter(&(&1.status == "delivered"))
      |> Enum.take(5)

    today_count = Orders.count_driver_deliveries_today(user_id)
    today_tips = Orders.sum_driver_tips_today(user_id)

    socket
    |> assign(:profile, profile)
    |> assign(:active_delivery, active_delivery)
    |> assign(:recent_deliveries, recent_deliveries)
    |> assign(:today_count, today_count)
    |> assign(:today_tips, today_tips)
  end

  defp status_label("available"), do: "Available"
  defp status_label("on_delivery"), do: "On Delivery"
  defp status_label(_), do: "Offline"

  defp status_text_color("available"), do: "text-green-600"
  defp status_text_color("on_delivery"), do: "text-orange-600"
  defp status_text_color(_), do: "text-gray-500"

  defp toggle_bg("available"), do: "bg-green-500"
  defp toggle_bg(_), do: "bg-gray-300"

  defp toggle_translate("available"), do: "translate-x-5"
  defp toggle_translate(_), do: "translate-x-0"

  defp delivery_status_color("assigned"), do: "bg-blue-100 text-blue-800"
  defp delivery_status_color("picked_up"), do: "bg-orange-100 text-orange-800"
  defp delivery_status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_status("picked_up"), do: "Picked Up"
  defp format_status("out_for_delivery"), do: "En Route"

  defp format_status(status),
    do:
      status
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp format_cents(nil), do: "0.00"

  defp format_cents(cents) when is_integer(cents),
    do: :erlang.float_to_binary(cents / 100, decimals: 2)

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    "#{dt.hour}:#{String.pad_leading(to_string(dt.minute), 2, "0")}"
  end
end
