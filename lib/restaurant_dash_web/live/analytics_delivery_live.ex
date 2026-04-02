defmodule RestaurantDashWeb.AnalyticsDeliveryLive do
  @moduledoc "Delivery metrics analytics page. Owner-only."
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Analytics, Tenancy}

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        {start_dt, end_dt} = Analytics.date_range(:last_30_days)

        socket =
          socket
          |> assign(:restaurant, restaurant)
          |> assign(:current_user, current_user)
          |> assign(:range, :last_30_days)
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

    {:noreply,
     socket
     |> assign(:range, range)
     |> load_analytics(restaurant_id, start_dt, end_dt)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-7xl mx-auto flex items-center gap-3">
          <a href="/dashboard" class="text-gray-500 hover:text-gray-700 text-sm">← Dashboard</a>
          <span class="text-gray-300">/</span>
          <h1 class="text-lg font-bold text-gray-900">Delivery Metrics</h1>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-8">
        <%!-- Date Range Picker --%>
        <div class="flex gap-2 mb-8 flex-wrap">
          <%= for r <- ~w(today this_week this_month last_30_days)a do %>
            <button
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
          <% end %>
        </div>

        <%!-- Delivery KPIs --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Avg Delivery Time</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {format_minutes(@metrics.avg_delivery_minutes)}
            </p>
            <p class="text-xs text-gray-400 mt-1">order placed → delivered</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Avg Prep Time</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {format_minutes(@metrics.avg_prep_minutes)}
            </p>
            <p class="text-xs text-gray-400 mt-1">accepted → ready</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Deliveries</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@metrics.delivered_count}</p>
            <p class="text-xs text-gray-400 mt-1">completed</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Cancellation Rate</p>
            <p class={[
              "text-3xl font-bold mt-1",
              if(@metrics.cancellation_rate > 10, do: "text-red-600", else: "text-gray-900")
            ]}>
              {@metrics.cancellation_rate}%
            </p>
            <p class="text-xs text-gray-400 mt-1">{@metrics.cancelled_count} cancelled</p>
          </div>
        </div>

        <%!-- Peak Delivery Hours --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6 mb-6">
          <h2 class="text-base font-semibold text-gray-800 mb-4">Peak Delivery Hours</h2>
          <%= if Enum.empty?(@orders_by_hour) do %>
            <p class="text-gray-400 text-sm text-center py-8">No data for this period</p>
          <% else %>
            <div class="flex items-end gap-1 h-32">
              <% max_count = @orders_by_hour |> Enum.map(& &1.count) |> Enum.max() %>
              <%= for entry <- @orders_by_hour do %>
                <div class="flex-1 flex flex-col items-center gap-1 group relative">
                  <span class="absolute -top-5 text-xs text-gray-600 opacity-0 group-hover:opacity-100 transition-opacity">
                    {entry.count}
                  </span>
                  <div
                    class="w-full bg-indigo-400 rounded-t"
                    style={"height: #{bar_height(entry.count, max_count)}px"}
                  >
                  </div>
                  <span class="text-xs text-gray-400">{entry.hour}</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Driver Performance --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <h2 class="text-base font-semibold text-gray-800 mb-4">Driver Performance</h2>
          <%= if Enum.empty?(@driver_metrics) do %>
            <p class="text-gray-400 text-sm text-center py-8">No delivery data for this period</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-100">
                    <th class="text-left py-2 text-gray-500 font-medium">Driver</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Deliveries</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Avg Time</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={d <- @driver_metrics} class="border-b border-gray-50">
                    <td class="py-2 text-gray-900">{d.driver_name}</td>
                    <td class="py-2 text-right font-medium text-gray-900">{d.delivery_count}</td>
                    <td class="py-2 text-right text-gray-700">
                      {format_minutes(d.avg_delivery_minutes)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp load_analytics(socket, restaurant_id, start_dt, end_dt) do
    socket
    |> assign(:metrics, Analytics.delivery_metrics(restaurant_id, start_dt, end_dt))
    |> assign(:driver_metrics, Analytics.delivery_by_driver(restaurant_id, start_dt, end_dt))
    |> assign(:orders_by_hour, Analytics.orders_by_hour(restaurant_id, start_dt, end_dt))
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
  defp range_label(:this_week), do: "This Week"
  defp range_label(:this_month), do: "This Month"
  defp range_label(:last_30_days), do: "Last 30 Days"
  defp range_label(_), do: "Custom"

  defp format_minutes(nil), do: "—"
  defp format_minutes(mins) when is_float(mins), do: "#{Float.round(mins, 0) |> trunc()}m"
  defp format_minutes(mins) when is_integer(mins), do: "#{mins}m"

  defp bar_height(_count, 0), do: 4
  defp bar_height(count, max), do: max(trunc(count / max * 100), 4)
end
