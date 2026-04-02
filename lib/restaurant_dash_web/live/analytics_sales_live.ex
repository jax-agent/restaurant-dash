defmodule RestaurantDashWeb.AnalyticsSalesLive do
  @moduledoc """
  Sales analytics report page.
  Shows revenue metrics, orders by day chart, and allows CSV export.
  Owner-only access.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Analytics, Tenancy}

  @ranges ~w(today yesterday this_week this_month last_30_days)a

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        range = :today
        {start_dt, end_dt} = Analytics.date_range(range)

        socket =
          socket
          |> assign(:restaurant, restaurant)
          |> assign(:current_user, current_user)
          |> assign(:range, range)
          |> assign(:ranges, @ranges)
          |> load_analytics(restaurant.id, start_dt, end_dt)

        {:ok, socket}

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
  def handle_event("set_range", %{"range" => range_str}, socket) do
    range = String.to_existing_atom(range_str)
    {start_dt, end_dt} = Analytics.date_range(range)
    restaurant_id = socket.assigns.restaurant.id

    socket =
      socket
      |> assign(:range, range)
      |> load_analytics(restaurant_id, start_dt, end_dt)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%!-- Header --%>
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-7xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-3">
            <a href="/dashboard" class="text-gray-500 hover:text-gray-700 text-sm">← Dashboard</a>
            <span class="text-gray-300">/</span>
            <h1 class="text-lg font-bold text-gray-900">Sales Report</h1>
          </div>
          <a
            href={"/dashboard/analytics/sales/export?range=#{@range}"}
            class="inline-flex items-center gap-2 px-4 py-2 bg-white border border-gray-300 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            ⬇️ Export CSV
          </a>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-8">
        <%!-- Date Range Picker --%>
        <div class="flex gap-2 mb-8 flex-wrap">
          <button
            :for={r <- @ranges}
            phx-click="set_range"
            phx-value-range={r}
            class={[
              "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@range == r,
                do: "bg-indigo-600 text-white",
                else: "bg-white border border-gray-200 text-gray-700 hover:bg-gray-50"
              )
            ]}
          >
            {range_label(r)}
          </button>
        </div>

        <%!-- Top-line Metrics --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Total Revenue</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Analytics.format_money(@summary.total_revenue)}
            </p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Total Orders</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@summary.order_count}</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Avg Order Value</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Analytics.format_money(@summary.avg_order_value)}
            </p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Tips Collected</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Analytics.format_money(@summary.total_tips)}
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <%!-- Orders by Day Chart (SVG) --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Orders by Day</h2>
            <%= if Enum.empty?(@orders_by_day) do %>
              <div class="h-48 flex items-center justify-center text-gray-400 text-sm">
                No order data for this period
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <.svg_bar_chart data={@orders_by_day} />
              </div>
            <% end %>
          </div>

          <%!-- Orders by Hour --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Orders by Hour</h2>
            <%= if Enum.empty?(@orders_by_hour) do %>
              <div class="h-48 flex items-center justify-center text-gray-400 text-sm">
                No data for this period
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <.svg_hour_chart data={@orders_by_hour} />
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Orders by Day Table --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6 mb-8">
          <h2 class="text-base font-semibold text-gray-800 mb-4">Daily Breakdown</h2>
          <%= if Enum.empty?(@orders_by_day) do %>
            <p class="text-gray-400 text-sm text-center py-8">No orders in this period</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-100">
                    <th class="text-left py-2 text-gray-500 font-medium">Date</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Orders</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @orders_by_day} class="border-b border-gray-50">
                    <td class="py-2 text-gray-700">{format_date(row.date)}</td>
                    <td class="py-2 text-right font-medium text-gray-900">{row.count}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <%!-- Order Status Breakdown --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <h2 class="text-base font-semibold text-gray-800 mb-4">Orders by Status</h2>
          <%= if map_size(@orders_by_status) == 0 do %>
            <p class="text-gray-400 text-sm text-center py-8">No orders in this period</p>
          <% else %>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              <div
                :for={{status, count} <- @orders_by_status}
                class="text-center p-3 bg-gray-50 rounded-lg"
              >
                <p class="text-2xl font-bold text-gray-900">{count}</p>
                <p class="text-xs text-gray-500 mt-1">{humanize_status(status)}</p>
              </div>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  # ── SVG Charts ─────────────────────────────────────────────────────────────

  defp svg_bar_chart(assigns) do
    data = assigns.data
    max_count = Enum.map(data, & &1.count) |> Enum.max(fn -> 1 end)
    bar_width = 30
    gap = 4
    chart_height = 160
    chart_width = chart_max(length(data) * (bar_width + gap), 300)

    bars =
      data
      |> Enum.with_index()
      |> Enum.map(fn {item, i} ->
        bar_height = chart_max(trunc(item.count / max_count * chart_height), 2)
        x = i * (bar_width + gap)
        y = chart_height - bar_height
        label = date_short(item.date)

        {x, y, bar_width, bar_height, label, item.count}
      end)

    assigns =
      assign(assigns,
        bars: bars,
        chart_height: chart_height,
        chart_width: chart_width,
        max_count: max_count
      )

    ~H"""
    <svg
      viewBox={"0 0 #{@chart_width} #{@chart_height + 30}"}
      class="w-full"
      style={"min-width: #{@chart_width}px"}
    >
      <%= for {x, y, w, h, label, count} <- @bars do %>
        <rect
          x={x}
          y={y}
          width={w}
          height={h}
          fill="#6366f1"
          rx="3"
          opacity="0.85"
        >
          <title>{count} orders</title>
        </rect>
        <text
          x={x + div(w, 2)}
          y={@chart_height + 20}
          text-anchor="middle"
          font-size="9"
          fill="#6b7280"
        >
          {label}
        </text>
      <% end %>
    </svg>
    """
  end

  defp svg_hour_chart(assigns) do
    data = assigns.data
    max_count = Enum.map(data, & &1.count) |> Enum.max(fn -> 1 end)
    bar_width = 20
    gap = 3
    chart_height = 120

    bars =
      data
      |> Enum.with_index()
      |> Enum.map(fn {item, i} ->
        bar_height = chart_max(trunc(item.count / max_count * chart_height), 2)
        x = i * (bar_width + gap)
        y = chart_height - bar_height
        label = "#{item.hour}h"
        {x, y, bar_width, bar_height, label, item.count}
      end)

    chart_width = chart_max(length(data) * (bar_width + gap), 200)

    assigns = assign(assigns, bars: bars, chart_height: chart_height, chart_width: chart_width)

    ~H"""
    <svg
      viewBox={"0 0 #{@chart_width} #{@chart_height + 25}"}
      class="w-full"
      style={"min-width: #{@chart_width}px"}
    >
      <%= for {x, y, w, h, label, count} <- @bars do %>
        <rect x={x} y={y} width={w} height={h} fill="#10b981" rx="2" opacity="0.8">
          <title>{count} orders</title>
        </rect>
        <text
          x={x + div(w, 2)}
          y={@chart_height + 18}
          text-anchor="middle"
          font-size="8"
          fill="#6b7280"
        >
          {label}
        </text>
      <% end %>
    </svg>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp load_analytics(socket, restaurant_id, start_dt, end_dt) do
    socket
    |> assign(:summary, Analytics.revenue_summary(restaurant_id, start_dt, end_dt))
    |> assign(:orders_by_day, Analytics.orders_by_day(restaurant_id, start_dt, end_dt))
    |> assign(:orders_by_hour, Analytics.orders_by_hour(restaurant_id, start_dt, end_dt))
    |> assign(:orders_by_status, Analytics.orders_by_status(restaurant_id, start_dt, end_dt))
    |> assign(:start_dt, start_dt)
    |> assign(:end_dt, end_dt)
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

  defp range_label(:today), do: "Today"
  defp range_label(:yesterday), do: "Yesterday"
  defp range_label(:this_week), do: "This Week"
  defp range_label(:this_month), do: "This Month"
  defp range_label(:last_30_days), do: "Last 30 Days"

  defp humanize_status("new"), do: "New"
  defp humanize_status("accepted"), do: "Accepted"
  defp humanize_status("preparing"), do: "Preparing"
  defp humanize_status("ready"), do: "Ready"
  defp humanize_status("out_for_delivery"), do: "Out for Delivery"
  defp humanize_status("delivered"), do: "Delivered"
  defp humanize_status("cancelled"), do: "Cancelled"
  defp humanize_status(s), do: s

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %d")
  defp format_date(str) when is_binary(str), do: str

  defp date_short(nil), do: ""
  defp date_short(%Date{} = d), do: Calendar.strftime(d, "%m/%d")
  defp date_short(str) when is_binary(str), do: str

  defp chart_max(a, b) when a > b, do: a
  defp chart_max(_a, b), do: b
end
