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
    <div
      class="min-h-screen"
      style="background: #FAFAFA; font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;"
    >
      <%!-- ═══ HEADER ═══ --%>
      <header
        class="bg-white/95 backdrop-blur-md border-b sticky top-0 z-30"
        style="border-color: #F3F4F6; box-shadow: 0 1px 0 rgba(0,0,0,0.04);"
      >
        <div class="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
          <%!-- Brand --%>
          <div class="flex items-center gap-3">
            <div
              class="w-9 h-9 rounded-xl flex items-center justify-center text-white font-bold text-sm flex-shrink-0 shadow-sm"
              style={"background: #{@restaurant.primary_color}"}
            >
              {String.first(@restaurant.name)}
            </div>
            <div>
              <h1 class="text-[15px] font-bold text-gray-900 leading-tight tracking-tight">
                {@restaurant.name}
              </h1>
              <p class="text-xs text-gray-400 hidden sm:block font-medium">Owner Dashboard</p>
            </div>
          </div>

          <%!-- Desktop nav --%>
          <nav class="hidden md:flex items-center gap-1 text-sm">
            <%= for {label, href} <- [
              {"Orders", "/dashboard/orders"},
              {"Menu", "/dashboard/menu"},
              {"Analytics", "/dashboard/analytics/sales"},
              {"Drivers", "/dashboard/drivers"},
              {"Promos", "/dashboard/promos"},
              {"Settings", "/dashboard/settings"}
            ] do %>
              <a
                href={href}
                class="px-3 py-1.5 rounded-lg text-gray-600 hover:text-gray-900 hover:bg-gray-50 font-medium transition-all text-[13px]"
              >
                {label}
              </a>
            <% end %>
            <%!-- Notification Bell --%>
            <div class="ml-1 rounded-full p-1.5" style={"background: #{@restaurant.primary_color}"}>
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
              class="ml-1 px-3 py-1.5 rounded-lg text-red-500 hover:text-red-700 hover:bg-red-50 font-medium transition-all text-[13px]"
            >
              Log out
            </a>
          </nav>

          <%!-- Mobile: bell + hamburger --%>
          <div class="flex items-center gap-2 md:hidden">
            <div class="rounded-full p-1" style={"background: #{@restaurant.primary_color}"}>
              <.live_component
                module={RestaurantDashWeb.NotificationBellLive}
                id="notification-bell-mobile"
                restaurant_id={@restaurant.id}
                user_id={@current_user.id}
              />
            </div>
            <button
              phx-click={JS.toggle(to: "#mobile-nav")}
              class="hamburger-btn"
              aria-label="Open menu"
            >
              ☰
            </button>
          </div>
        </div>

        <%!-- Mobile nav drawer --%>
        <div id="mobile-nav" class="hidden md:hidden border-t bg-white" style="border-color: #F3F4F6;">
          <nav class="px-4 py-3 space-y-0.5">
            <a href="/dashboard/orders" class="mobile-nav-link">📋 Orders</a>
            <a href="/dashboard/menu" class="mobile-nav-link">🍽️ Menu</a>
            <a href="/dashboard/analytics/sales" class="mobile-nav-link">📈 Analytics</a>
            <a href="/dashboard/drivers" class="mobile-nav-link">🚗 Drivers</a>
            <a href="/dashboard/settings" class="mobile-nav-link">⚙️ Settings</a>
            <a href="/dashboard/notifications" class="mobile-nav-link">🔔 Alerts</a>
            <a href="/dashboard/promos" class="mobile-nav-link">🎟️ Promos</a>
            <a href="/dashboard/loyalty" class="mobile-nav-link">⭐ Loyalty</a>
            <a href="/dashboard/locations" class="mobile-nav-link">📍 Locations</a>
            <a href="/dashboard/hours" class="mobile-nav-link">🕐 Hours</a>
            <div class="border-t pt-2 mt-2" style="border-color: #F3F4F6;">
              <a href="/users/log-out" data-method="delete" class="mobile-nav-link text-red-500">
                🚪 Log out
              </a>
            </div>
          </nav>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-8">
        <%!-- ═══ ANALYTICS OVERVIEW CARDS ═══ --%>
        <div>
          <div class="section-header mb-5">
            <h2 class="section-title text-lg">Today's Overview</h2>
            <a href="/dashboard/analytics/sales" class="section-link">Full report →</a>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <%!-- Revenue --%>
            <div class="stat-card stat-card--green">
              <div class="stat-icon stat-icon--green">💰</div>
              <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">
                Today's Revenue
              </p>
              <p class="text-3xl font-extrabold text-gray-900 tracking-tight">
                {Analytics.format_money(@analytics.today_revenue)}
              </p>
              <div class="mt-2 flex items-center gap-1 text-xs">
                {render_trend(@analytics.revenue_change)}
                <span class="text-gray-400">vs yesterday</span>
              </div>
            </div>

            <%!-- Orders --%>
            <div class="stat-card stat-card--blue">
              <div class="stat-icon stat-icon--blue">📋</div>
              <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">Orders</p>
              <p class="text-3xl font-extrabold text-gray-900 tracking-tight">
                {@analytics.today_orders}
              </p>
              <div class="mt-2 flex items-center gap-1 text-xs">
                {render_trend(@analytics.orders_change)}
                <span class="text-gray-400">vs yesterday</span>
              </div>
            </div>

            <%!-- Avg Order Value --%>
            <div class="stat-card stat-card--purple">
              <div class="stat-icon stat-icon--purple">🧾</div>
              <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">
                Avg Order
              </p>
              <p class="text-3xl font-extrabold text-gray-900 tracking-tight">
                {Analytics.format_money(@analytics.today_avg_order)}
              </p>
              <p class="text-xs text-gray-400 mt-2">Today's average</p>
            </div>

            <%!-- Active --%>
            <div class="stat-card stat-card--orange">
              <div class="stat-icon stat-icon--orange">🔥</div>
              <p class="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">Active</p>
              <p class="text-3xl font-extrabold text-gray-900 tracking-tight">
                {@analytics.active_orders}
              </p>
              <%= if @analytics.avg_delivery_minutes do %>
                <p class="text-xs text-gray-400 mt-2">
                  Avg {@analytics.avg_delivery_minutes}m delivery
                </p>
              <% else %>
                <p class="text-xs text-gray-400 mt-2">In progress right now</p>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Total Orders (legacy test requirement) --%>
        <div class="flex items-center gap-6 text-sm">
          <span class="text-gray-400 font-medium">Total Orders</span>
          <span class="font-bold text-gray-900">{@total_count}</span>
        </div>

        <%!-- ═══ QUICK ACTIONS ═══ --%>
        <div class="flex gap-3 flex-wrap">
          <a href="/dashboard/analytics/sales" class="quick-link-pill">📈 Sales</a>
          <a href="/dashboard/analytics/items" class="quick-link-pill">🍕 Popular Items</a>
          <a href="/dashboard/analytics/delivery" class="quick-link-pill">🚗 Delivery</a>
          <a href="/dashboard/analytics/customers" class="quick-link-pill">👥 Customers</a>
          <a href="/dashboard/menu" class="quick-link-pill">🍽️ Menu</a>
          <a href="/dashboard/promos" class="quick-link-pill">🎟️ Promos</a>
        </div>

        <%!-- ═══ ORDER STATUS BREAKDOWN ═══ --%>
        <div
          class="bg-white rounded-2xl border p-6"
          style="border-color: #F3F4F6; box-shadow: 0 1px 3px rgba(0,0,0,0.06);"
        >
          <div class="section-header">
            <h2 class="section-title">Orders by Status</h2>
            <a href="/dashboard/orders" class="section-link">View Kanban →</a>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3">
            <%= for status <- @statuses do %>
              <% count = Map.get(@status_counts, status, 0) %>
              <a
                href={"/dashboard/orders?status=#{status}"}
                class="flex flex-col items-center p-4 rounded-xl border text-center transition-all hover:shadow-sm hover:border-gray-300"
                style="border-color: #F3F4F6;"
              >
                <span class="text-2xl font-extrabold text-gray-900 tracking-tight">{count}</span>
                <span class={"mt-1.5 badge badge-#{status}"}>
                  {humanize_status(status)}
                </span>
              </a>
            <% end %>
          </div>
        </div>

        <%!-- ═══ RECENT ORDERS (card-based) ═══ --%>
        <div
          class="bg-white rounded-2xl border p-6"
          style="border-color: #F3F4F6; box-shadow: 0 1px 3px rgba(0,0,0,0.06);"
        >
          <div class="section-header">
            <h2 class="section-title">Recent Orders</h2>
            <a href="/dashboard/orders" class="section-link">View all →</a>
          </div>

          <%= if Enum.empty?(@recent_orders) do %>
            <div class="empty-state">
              <span class="empty-state-icon">📭</span>
              <h3 class="empty-state-title">No orders yet</h3>
              <p class="empty-state-text">
                Orders will appear here as customers place them.
              </p>
            </div>
          <% else %>
            <div class="space-y-2" id="recent-orders">
              <%= for order <- @recent_orders do %>
                <div
                  class="order-row-card"
                  id={"dashboard-order-#{order.id}"}
                  style={"border-left: 3px solid #{order_status_color(order.status)}"}
                >
                  <div class="flex items-center gap-3 flex-1 min-w-0">
                    <div class="min-w-0">
                      <p class="font-semibold text-gray-900 text-sm truncate">
                        {order.customer_name}
                      </p>
                      <p class="text-xs text-gray-400">
                        {length(order.items)} item{if length(order.items) != 1, do: "s"}
                      </p>
                    </div>
                  </div>
                  <span class={"badge badge-#{order.status} flex-shrink-0"}>
                    {humanize_status(order.status)}
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- ═══ DRIVER RATINGS ═══ --%>
        <%= if length(@driver_ratings) > 0 do %>
          <div
            class="bg-white rounded-2xl border p-6"
            style="border-color: #F3F4F6; box-shadow: 0 1px 3px rgba(0,0,0,0.06);"
          >
            <div class="section-header">
              <h2 class="section-title">Driver Ratings</h2>
              <a href="/dashboard/drivers" class="section-link">View all →</a>
            </div>
            <div class="space-y-3">
              <%= for %{profile: profile, avg_rating: avg, rating_count: count, low_rated: low_rated} <- @driver_ratings do %>
                <div class={"order-row-card #{if low_rated, do: "border-l-4 border-l-red-400"}"}>
                  <div class="flex-1 min-w-0">
                    <p class="font-semibold text-sm text-gray-900">
                      {profile.user && (profile.user.name || profile.user.email)}
                    </p>
                    <p class="text-xs text-gray-400">{profile.vehicle_type}</p>
                    <%= if low_rated do %>
                      <p class="text-xs text-red-600 font-semibold mt-0.5">⚠️ Low rating alert</p>
                    <% end %>
                  </div>
                  <div class="text-right flex-shrink-0">
                    <%= if avg do %>
                      <p class="font-bold text-sm text-gray-900">⭐ {Float.round(avg, 1)}</p>
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

        <%!-- ═══ DRIVER EARNINGS ═══ --%>
        <%= if length(@earnings) > 0 do %>
          <div
            class="bg-white rounded-2xl border p-6"
            style="border-color: #F3F4F6; box-shadow: 0 1px 3px rgba(0,0,0,0.06);"
          >
            <div class="section-header">
              <h2 class="section-title">Recent Driver Earnings</h2>
              <a href="/dashboard/drivers" class="section-link">View all →</a>
            </div>
            <div class="space-y-2">
              <%= for earning <- @earnings do %>
                <div class="order-row-card">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-semibold text-gray-900">
                      {earning.driver_profile && earning.driver_profile.user &&
                        (earning.driver_profile.user.name || earning.driver_profile.user.email)}
                    </p>
                    <p class="text-xs text-gray-400">Order #{earning.order_id}</p>
                  </div>
                  <div class="text-right flex-shrink-0">
                    <p class="text-sm font-bold text-green-600">
                      ${format_cents(earning.total_earned)}
                    </p>
                    <p class="text-xs text-gray-400">
                      Base ${format_cents(earning.base_pay)} + tip ${format_cents(earning.tip_amount)}
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- ═══ SCHEDULED ORDERS ═══ --%>
        <% scheduled = Orders.list_scheduled_orders(@restaurant.id) %>
        <%= if length(scheduled) > 0 do %>
          <div
            class="bg-white rounded-2xl border border-indigo-100 p-6"
            style="box-shadow: 0 1px 3px rgba(0,0,0,0.06);"
          >
            <div class="section-header">
              <h2 class="section-title">⏰ Scheduled Orders ({length(scheduled)})</h2>
            </div>
            <div class="space-y-2">
              <%= for order <- scheduled do %>
                <div class="order-row-card">
                  <div class="flex-1 min-w-0">
                    <p class="font-semibold text-gray-900">{order.customer_name}</p>
                    <p class="text-sm text-gray-500 truncate">{order.delivery_address}</p>
                  </div>
                  <div class="text-right flex-shrink-0">
                    <p class="text-sm font-bold text-indigo-600">
                      {if order.scheduled_for,
                        do: Calendar.strftime(order.scheduled_for, "%b %-d at %-I:%M %p")}
                    </p>
                    <a
                      href={"/orders/#{order.id}/track"}
                      class="text-xs text-gray-400 hover:text-gray-700"
                    >
                      View →
                    </a>
                  </div>
                </div>
              <% end %>
            </div>
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
  defp humanize_status("scheduled"), do: "Scheduled"
  defp humanize_status("accepted"), do: "Accepted"
  defp humanize_status("preparing"), do: "Preparing"
  defp humanize_status("ready"), do: "Ready"
  defp humanize_status("assigned"), do: "Assigned"
  defp humanize_status("picked_up"), do: "Picked Up"
  defp humanize_status("out_for_delivery"), do: "Out for Delivery"
  defp humanize_status("delivered"), do: "Delivered"
  defp humanize_status("cancelled"), do: "Cancelled"
  defp humanize_status(s), do: s

  defp order_status_color("new"), do: "#3B82F6"
  defp order_status_color("scheduled"), do: "#8B5CF6"
  defp order_status_color("accepted"), do: "#10B981"
  defp order_status_color("preparing"), do: "#F59E0B"
  defp order_status_color("ready"), do: "#10B981"
  defp order_status_color("assigned"), do: "#6366F1"
  defp order_status_color("picked_up"), do: "#F59E0B"
  defp order_status_color("out_for_delivery"), do: "#10B981"
  defp order_status_color("delivered"), do: "#9CA3AF"
  defp order_status_color("cancelled"), do: "#EF4444"
  defp order_status_color(_), do: "#E5E7EB"
end
