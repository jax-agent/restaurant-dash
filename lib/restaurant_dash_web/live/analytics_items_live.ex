defmodule RestaurantDashWeb.AnalyticsItemsLive do
  @moduledoc "Popular items analytics report. Owner-only."
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
          <h1 class="text-lg font-bold text-gray-900">Popular Items</h1>
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

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <%!-- Top 10 Items --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Top 10 Items</h2>
            <%= if Enum.empty?(@top_items) do %>
              <p class="text-gray-400 text-sm text-center py-8">No order data for this period</p>
            <% else %>
              <div class="space-y-3">
                <%= for {item, i} <- Enum.with_index(@top_items, 1) do %>
                  <div class="flex items-center gap-3">
                    <span class="text-xs font-bold text-gray-400 w-5 text-center">{i}</span>
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-gray-900 truncate">{item.name}</p>
                      <div class="mt-1 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                        <div
                          class="h-full bg-indigo-500 rounded-full"
                          style={"width: #{item_bar_pct(item, @top_items)}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <div class="text-right text-xs">
                      <p class="font-semibold text-gray-900">{item.total_quantity} orders</p>
                      <p class="text-gray-400">{Analytics.format_money(item.total_revenue)}</p>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Revenue by Category --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Revenue by Category</h2>
            <%= if Enum.empty?(@revenue_by_category) do %>
              <p class="text-gray-400 text-sm text-center py-8">No data for this period</p>
            <% else %>
              <div class="space-y-3">
                <%= for cat <- @revenue_by_category do %>
                  <div class="flex items-center justify-between py-2 border-b border-gray-50">
                    <div>
                      <p class="text-sm font-medium text-gray-900">{cat.category_name}</p>
                      <p class="text-xs text-gray-400">{cat.item_count} items sold</p>
                    </div>
                    <p class="text-sm font-semibold text-gray-900">
                      {Analytics.format_money(cat.total_revenue)}
                    </p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Least Popular Items --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <h2 class="text-base font-semibold text-gray-800 mb-1">Least Popular Items</h2>
          <p class="text-xs text-gray-400 mb-4">Consider removing or promoting these items</p>
          <%= if Enum.empty?(@least_popular) do %>
            <p class="text-gray-400 text-sm text-center py-8">No data for this period</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-100">
                    <th class="text-left py-2 text-gray-500 font-medium">Item</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Qty Sold</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={item <- @least_popular} class="border-b border-gray-50">
                    <td class="py-2 text-gray-700">{item.name}</td>
                    <td class="py-2 text-right text-gray-900 font-medium">{item.total_quantity}</td>
                    <td class="py-2 text-right text-gray-900">
                      {Analytics.format_money(item.total_revenue)}
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
    |> assign(:top_items, Analytics.top_items(restaurant_id, start_dt, end_dt))
    |> assign(:least_popular, Analytics.least_popular_items(restaurant_id, start_dt, end_dt))
    |> assign(:revenue_by_category, Analytics.revenue_by_category(restaurant_id, start_dt, end_dt))
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

  defp item_bar_pct(_item, []), do: 0

  defp item_bar_pct(item, all_items) do
    max_qty = all_items |> Enum.map(& &1.total_quantity) |> Enum.max()
    if max_qty > 0, do: round(item.total_quantity / max_qty * 100), else: 0
  end
end
