defmodule RestaurantDashWeb.OwnerDashboardLive do
  @moduledoc """
  Owner-facing dashboard. Shows scoped stats and orders for the owner's restaurant.
  Requires owner or staff role.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Orders, Drivers, Tenancy, Analytics}
  alias RestaurantDash.Orders.Order

  @statuses Order.valid_statuses()

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        if connected?(socket) do
          Orders.subscribe(restaurant.id)
        end

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:restaurant, restaurant)
          |> assign(:statuses, @statuses)
          |> load_stats(restaurant.id)

        {:ok, socket}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to access the dashboard.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to access the owner dashboard.")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:order_created, _order}, socket) do
    {:noreply, load_stats(socket, socket.assigns.restaurant.id)}
  end

  @impl true
  def handle_info({:order_updated, _order}, socket) do
    {:noreply, load_stats(socket, socket.assigns.restaurant.id)}
  end

  @impl true
  def handle_info({:order_position_updated, _order}, socket) do
    {:noreply, load_stats(socket, socket.assigns.restaurant.id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%!-- Header --%>
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-7xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div
              class="w-8 h-8 rounded-lg flex items-center justify-center text-white font-bold text-sm"
              style={"background-color: #{@restaurant.primary_color}"}
            >
              {String.first(@restaurant.name)}
            </div>
            <div>
              <h1 class="text-lg font-bold text-gray-900">{@restaurant.name}</h1>
              <p class="text-xs text-gray-500">Owner Dashboard</p>
            </div>
          </div>

          <nav class="flex items-center gap-4 text-sm">
            <a href="/dashboard/orders" class="text-gray-600 hover:text-gray-900 font-medium">
              Orders
            </a>
            <a href="/dashboard/menu" class="text-gray-600 hover:text-gray-900 font-medium">
              Menu
            </a>
            <a
              href="/dashboard/analytics/sales"
              class="text-gray-600 hover:text-gray-900 font-medium"
            >
              Analytics
            </a>
            <a
              href="/dashboard/settings"
              class="text-gray-600 hover:text-gray-900 font-medium"
            >
              Settings
            </a>
            <a
              href="/dashboard/notifications"
              class="text-gray-600 hover:text-gray-900 font-medium"
            >
              Alerts
            </a>
            <%!-- Notification Bell --%>
            <div
              class="rounded-full p-1"
              style={"background-color: #{@restaurant.primary_color}"}
            >
              <.live_component
                module={RestaurantDashWeb.NotificationBellLive}
                id="notification-bell"
                restaurant_id={@restaurant.id}
                user_id={@current_user.id}
              />
            </div>
            <a
              href="/users/log-out"
              data-method="delete"
              class="text-red-500 hover:text-red-700 font-medium"
            >
              Log out
            </a>
          </nav>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-8">
        <%!-- Analytics Overview Cards --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <%!-- Today's Revenue --%>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Today's Revenue</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Analytics.format_money(@analytics.today_revenue)}
            </p>
            <div class="mt-2 flex items-center gap-1 text-xs">
              {render_trend(@analytics.revenue_change)}
              <span class="text-gray-400">vs yesterday</span>
            </div>
          </div>
          <%!-- Today's Orders --%>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Today's Orders</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@analytics.today_orders}</p>
            <div class="mt-2 flex items-center gap-1 text-xs">
              {render_trend(@analytics.orders_change)}
              <span class="text-gray-400">vs yesterday</span>
            </div>
          </div>
          <%!-- Avg Order Value --%>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Avg Order Value</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Analytics.format_money(@analytics.today_avg_order)}
            </p>
            <p class="text-xs text-gray-400 mt-2">Today</p>
          </div>
          <%!-- Active Orders --%>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Active Orders</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@analytics.active_orders}</p>
            <%= if @analytics.avg_delivery_minutes do %>
              <p class="text-xs text-gray-400 mt-2">
                Avg delivery: {@analytics.avg_delivery_minutes}m today
              </p>
            <% else %>
              <p class="text-xs text-gray-400 mt-2">In progress right now</p>
            <% end %>
          </div>
        </div>

        <%!-- Quick Analytics Links --%>
        <div class="mb-8 flex gap-3 flex-wrap">
          <a
            href="/dashboard/analytics/sales"
            class="inline-flex items-center gap-2 px-4 py-2 bg-white border border-gray-200 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            📈 Sales Report
          </a>
          <a
            href="/dashboard/analytics/items"
            class="inline-flex items-center gap-2 px-4 py-2 bg-white border border-gray-200 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            🍕 Popular Items
          </a>
          <a
            href="/dashboard/analytics/delivery"
            class="inline-flex items-center gap-2 px-4 py-2 bg-white border border-gray-200 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            🚗 Delivery Metrics
          </a>
          <a
            href="/dashboard/analytics/customers"
            class="inline-flex items-center gap-2 px-4 py-2 bg-white border border-gray-200 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            👥 Customer Insights
          </a>
        </div>

        <%!-- Legacy Stats cards --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Today's Orders</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@today_count}</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Total Orders</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@total_count}</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Active Orders</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Map.get(@status_counts, "new", 0) + Map.get(@status_counts, "preparing", 0)}
            </p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Out for Delivery</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Map.get(@status_counts, "out_for_delivery", 0)}
            </p>
          </div>
        </div>

        <%!-- Order status breakdown --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6 mb-8">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-base font-semibold text-gray-800">Orders by Status</h2>
            <a
              href="/dashboard/orders"
              class="text-sm font-medium"
              style={"color: #{@restaurant.primary_color}"}
            >
              View all →
            </a>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <%= for status <- @statuses do %>
              <div class="text-center p-3 bg-gray-50 rounded-lg">
                <p class="text-2xl font-bold text-gray-900">
                  {Map.get(@status_counts, status, 0)}
                </p>
                <p class="text-xs text-gray-500 mt-1">{humanize_status(status)}</p>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Recent orders --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-base font-semibold text-gray-800">Recent Orders</h2>
            <a
              href="/dashboard/orders"
              class="text-sm font-medium"
              style={"color: #{@restaurant.primary_color}"}
            >
              View Kanban →
            </a>
          </div>

          <%= if Enum.empty?(@recent_orders) do %>
            <div class="text-center py-12 text-gray-400">
              <p class="text-lg">No orders yet</p>
              <p class="text-sm mt-1">Orders will appear here when customers place them.</p>
            </div>
          <% else %>
            <div class="space-y-2" id="recent-orders">
              <%= for order <- @recent_orders do %>
                <div
                  class="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
                  id={"dashboard-order-#{order.id}"}
                >
                  <div>
                    <p class="font-medium text-gray-900 text-sm">{order.customer_name}</p>
                    <p class="text-xs text-gray-500">{length(order.items)} items</p>
                  </div>
                  <span class={"text-xs font-medium px-2 py-1 rounded-full #{status_badge_class(order.status)}"}>
                    {humanize_status(order.status)}
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        <%!-- Driver Ratings & Earnings --%>
        <%= if length(@driver_ratings) > 0 do %>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Driver Ratings</h2>
            <div class="space-y-3">
              <%= for %{profile: profile, avg_rating: avg, rating_count: count, low_rated: low_rated} <- @driver_ratings do %>
                <div class={"flex items-center justify-between p-3 rounded-lg #{if low_rated, do: "bg-red-50 border border-red-200", else: "bg-gray-50"}"}>
                  <div>
                    <p class="font-medium text-sm text-gray-900">
                      {profile.user && (profile.user.name || profile.user.email)}
                    </p>
                    <p class="text-xs text-gray-500">{profile.vehicle_type}</p>
                    <%= if low_rated do %>
                      <p class="text-xs text-red-600 font-medium mt-0.5">⚠️ Low rating alert</p>
                    <% end %>
                  </div>
                  <div class="text-right">
                    <%= if avg do %>
                      <p class="font-semibold text-sm">⭐ {Float.round(avg, 1)}</p>
                      <p class="text-xs text-gray-400">{count} reviews</p>
                    <% else %>
                      <p class="text-xs text-gray-400">No ratings yet</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Recent Earnings (Payout Report) --%>
        <%= if length(@earnings) > 0 do %>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Recent Driver Earnings</h2>
            <div class="space-y-2">
              <%= for earning <- @earnings do %>
                <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div>
                    <p class="text-sm font-medium text-gray-900">
                      {earning.driver_profile && earning.driver_profile.user &&
                        (earning.driver_profile.user.name || earning.driver_profile.user.email)}
                    </p>
                    <p class="text-xs text-gray-500">Order #{earning.order_id}</p>
                  </div>
                  <div class="text-right">
                    <p class="text-sm font-semibold text-green-600">
                      ${format_cents(earning.total_earned)}
                    </p>
                    <p class="text-xs text-gray-400">
                      Base ${format_cents(earning.base_pay)} + Tip ${format_cents(earning.tip_amount)}
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
            <a
              href="/dashboard/drivers"
              class="mt-3 inline-block text-sm text-blue-600 hover:underline"
            >
              View all drivers →
            </a>
          </div>
        <% end %>
      </main>
    </div>
    """
  end

  defp format_cents(nil), do: "0.00"
  defp format_cents(0), do: "0.00"

  defp format_cents(cents) when is_integer(cents),
    do: :erlang.float_to_binary(cents / 100, decimals: 2)

  defp render_trend(change) when change > 0,
    do: Phoenix.HTML.raw("<span class=\"text-green-600 font-medium\">↑ #{change}%</span>")

  defp render_trend(change) when change < 0,
    do: Phoenix.HTML.raw("<span class=\"text-red-600 font-medium\">↓ #{abs(change)}%</span>")

  defp render_trend(_),
    do: Phoenix.HTML.raw("<span class=\"text-gray-400 font-medium\">→ 0%</span>")

  # ─── Private ──────────────────────────────────────────────────────────────

  defp load_stats(socket, restaurant_id) do
    recent = Orders.list_orders(restaurant_id) |> Enum.take(-10) |> Enum.reverse()

    # Driver ratings: load all driver profiles with avg rating
    driver_profiles =
      Drivers.list_profiles()
      |> Enum.filter(&(&1.user && &1.user.restaurant_id == restaurant_id))

    driver_ratings =
      Enum.map(driver_profiles, fn profile ->
        {avg, count} = Orders.get_driver_average_rating(profile.user_id)

        %{
          profile: profile,
          avg_rating: avg,
          rating_count: count,
          low_rated: avg != nil and avg < 3.5
        }
      end)

    # Earnings report for restaurant
    earnings = Drivers.list_earnings_report(restaurant_id) |> Enum.take(20)

    # Analytics overview
    analytics = Analytics.dashboard_overview(restaurant_id)

    socket
    |> assign(:today_count, Orders.count_today(restaurant_id))
    |> assign(:total_count, Orders.count_total(restaurant_id))
    |> assign(:status_counts, Orders.count_by_status(restaurant_id))
    |> assign(:recent_orders, recent)
    |> assign(:driver_ratings, driver_ratings)
    |> assign(:earnings, earnings)
    |> assign(:analytics, analytics)
  end

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

  defp authorize(user) do
    if user.role in ~w(owner staff) do
      case user.restaurant_id && Tenancy.get_restaurant(user.restaurant_id) do
        nil -> {:error, :unauthorized}
        restaurant -> {:ok, restaurant}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp humanize_status("new"), do: "New"
  defp humanize_status("accepted"), do: "Accepted"
  defp humanize_status("preparing"), do: "Preparing"
  defp humanize_status("ready"), do: "Ready"
  defp humanize_status("out_for_delivery"), do: "Out for Delivery"
  defp humanize_status("delivered"), do: "Delivered"
  defp humanize_status("cancelled"), do: "Cancelled"
  defp humanize_status(s), do: s

  defp status_badge_class("new"), do: "bg-blue-100 text-blue-700"
  defp status_badge_class("preparing"), do: "bg-yellow-100 text-yellow-700"
  defp status_badge_class("out_for_delivery"), do: "bg-purple-100 text-purple-700"
  defp status_badge_class("delivered"), do: "bg-green-100 text-green-700"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-700"
end
