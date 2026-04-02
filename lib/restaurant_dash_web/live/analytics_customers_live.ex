defmodule RestaurantDashWeb.AnalyticsCustomersLive do
  @moduledoc "Customer insights analytics page. Owner-only."
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
          <h1 class="text-lg font-bold text-gray-900">Customer Insights</h1>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-8">
        <%!-- Date Range Picker --%>
        <div class="flex gap-2 mb-8 flex-wrap">
          <%= for r <- ~w(this_week this_month last_30_days)a do %>
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

        <%!-- Customer KPIs --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Unique Customers</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@summary.unique_customers}</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Repeat Customers</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@summary.repeat_customers}</p>
            <p class="text-xs text-gray-400 mt-1">ordered more than once</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Repeat Rate</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">{@summary.repeat_rate}%</p>
          </div>
          <div class="bg-white rounded-xl border border-gray-200 p-5">
            <p class="text-sm text-gray-500">Avg Lifetime Value</p>
            <p class="text-3xl font-bold text-gray-900 mt-1">
              {Analytics.format_money(@summary.avg_lifetime_value)}
            </p>
          </div>
        </div>

        <%!-- Top Customers --%>
        <div class="bg-white rounded-xl border border-gray-200 p-6">
          <h2 class="text-base font-semibold text-gray-800 mb-4">Top Customers by Spend</h2>
          <%= if Enum.empty?(@top_customers) do %>
            <p class="text-gray-400 text-sm text-center py-8">No customer data for this period</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-100">
                    <th class="text-left py-2 text-gray-500 font-medium">Customer</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Orders</th>
                    <th class="text-right py-2 text-gray-500 font-medium">Total Spend</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={c <- @top_customers} class="border-b border-gray-50">
                    <td class="py-2">
                      <p class="font-medium text-gray-900">{c.customer_name || "—"}</p>
                      <p class="text-xs text-gray-400">{mask_email(c.customer_email)}</p>
                    </td>
                    <td class="py-2 text-right font-medium text-gray-900">{c.order_count}</td>
                    <td class="py-2 text-right font-semibold text-gray-900">
                      {Analytics.format_money(c.total_spend)}
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
    |> assign(:summary, Analytics.customer_summary(restaurant_id, start_dt, end_dt))
    |> assign(:top_customers, Analytics.top_customers(restaurant_id, start_dt, end_dt))
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

  defp range_label(:this_week), do: "This Week"
  defp range_label(:this_month), do: "This Month"
  defp range_label(:last_30_days), do: "Last 30 Days"
  defp range_label(_), do: "Custom"

  # Partially mask email for privacy display
  defp mask_email(nil), do: "—"

  defp mask_email(email) do
    case String.split(email, "@") do
      [local, domain] when byte_size(local) > 2 ->
        masked =
          String.first(local) <> String.duplicate("*", byte_size(local) - 2) <> String.last(local)

        "#{masked}@#{domain}"

      _ ->
        "***@***"
    end
  end
end
