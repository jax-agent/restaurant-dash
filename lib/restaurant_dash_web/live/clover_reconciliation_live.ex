defmodule RestaurantDashWeb.CloverReconciliationLive do
  @moduledoc """
  Clover Payment Reconciliation dashboard.
  Shows matched/unmatched orders between our system and Clover,
  flags discrepancies, and allows CSV export.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Tenancy}
  alias RestaurantDash.Integrations.Clover, as: CloverIntegration

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:restaurant, restaurant)
          |> assign(:loading, false)
          |> assign(:reconciliation, nil)
          |> assign(:error, nil)

        socket =
          if CloverIntegration.connected?(restaurant) do
            load_reconciliation(socket, restaurant)
          else
            socket
          end

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
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_reconciliation(socket, socket.assigns.restaurant)}
  end

  @impl true
  def handle_event("export-csv", _params, socket) do
    restaurant = socket.assigns.restaurant

    case CloverIntegration.export_reconciliation_csv(restaurant) do
      {:ok, csv} ->
        {:noreply,
         socket
         |> push_event("download-csv", %{
           content: csv,
           filename: "clover_reconciliation_#{Date.utc_today()}.csv"
         })}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Export failed: #{inspect(reason)}")}
    end
  end

  defp load_reconciliation(socket, restaurant) do
    case CloverIntegration.reconcile_payments(restaurant) do
      {:ok, data} ->
        assign(socket, :reconciliation, data)

      {:error, reason} ->
        socket
        |> assign(:error, reason)
        |> put_flash(:error, "Failed to load reconciliation data: #{inspect(reason)}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-5xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-3">
            <a href="/dashboard" class="text-gray-500 hover:text-gray-700">← Dashboard</a>
            <span class="text-gray-300">|</span>
            <h1 class="text-lg font-bold text-gray-900">Clover Payment Reconciliation</h1>
          </div>
          <%= if CloverIntegration.mock_mode?() do %>
            <span class="text-xs bg-yellow-100 text-yellow-700 px-2 py-1 rounded-full font-medium">
              Demo Mode
            </span>
          <% end %>
        </div>
      </header>

      <main class="max-w-5xl mx-auto px-6 py-8">
        <%= if not CloverIntegration.connected?(@restaurant) do %>
          <div class="text-center py-16">
            <div class="text-4xl mb-4">🔌</div>
            <h2 class="text-xl font-semibold text-gray-700 mb-2">Clover Not Connected</h2>
            <p class="text-gray-500 mb-6">
              Connect your Clover POS to view payment reconciliation.
            </p>
            <a
              href="/dashboard/settings"
              class="px-4 py-2 bg-green-600 text-white rounded-lg text-sm font-semibold hover:bg-green-700"
            >
              Go to Settings
            </a>
          </div>
        <% else %>
          <%!-- Action Bar --%>
          <div class="flex items-center justify-between mb-6">
            <div>
              <p class="text-sm text-gray-500">
                Reconcile payments between Order Base and your Clover POS
              </p>
            </div>
            <div class="flex gap-3">
              <button
                phx-click="refresh"
                class="px-3 py-1.5 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50"
              >
                🔄 Refresh
              </button>
              <button
                phx-click="export-csv"
                class="px-3 py-1.5 bg-blue-600 text-white text-sm font-semibold rounded-lg hover:bg-blue-700"
              >
                📥 Export CSV
              </button>
            </div>
          </div>

          <%= if @reconciliation do %>
            <%!-- Summary Cards --%>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
              <div class="bg-white rounded-xl border border-gray-200 p-4 text-center">
                <p class="text-2xl font-bold text-gray-900">
                  {@reconciliation.summary.total_clover_payments}
                </p>
                <p class="text-xs text-gray-500 mt-1">Total Clover Payments</p>
              </div>
              <div class="bg-white rounded-xl border border-green-200 p-4 text-center">
                <p class="text-2xl font-bold text-green-600">
                  {@reconciliation.summary.matched_count}
                </p>
                <p class="text-xs text-gray-500 mt-1">Matched</p>
              </div>
              <div class="bg-white rounded-xl border border-orange-200 p-4 text-center">
                <p class="text-2xl font-bold text-orange-500">
                  {@reconciliation.summary.unmatched_count}
                </p>
                <p class="text-xs text-gray-500 mt-1">Unmatched</p>
              </div>
              <div class="bg-white rounded-xl border border-red-200 p-4 text-center">
                <p class="text-2xl font-bold text-red-500">
                  {@reconciliation.summary.discrepancy_count}
                </p>
                <p class="text-xs text-gray-500 mt-1">Discrepancies</p>
              </div>
            </div>

            <%!-- Discrepancies Alert --%>
            <%= if @reconciliation.discrepancies != [] do %>
              <div class="bg-red-50 border border-red-200 rounded-xl p-4 mb-6">
                <h3 class="font-semibold text-red-800 mb-2">
                  ⚠️ Amount Discrepancies Found
                </h3>
                <div class="space-y-2">
                  <%= for disc <- @reconciliation.discrepancies do %>
                    <div class="flex items-center justify-between text-sm">
                      <span class="text-red-700 font-mono">
                        Order #{disc.order_id} / Clover {disc.clover_order_id}
                      </span>
                      <span class="text-red-600">
                        Ours: ${format_cents(disc.our_amount)} · Clover: ${format_cents(
                          disc.clover_amount
                        )} · Diff: ${format_cents(disc.difference)}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Matched Payments --%>
            <div class="bg-white rounded-xl border border-gray-200 mb-6">
              <div class="px-4 py-3 border-b border-gray-100">
                <h3 class="font-semibold text-gray-800">
                  Matched Payments ({length(@reconciliation.matched)})
                </h3>
              </div>
              <%= if @reconciliation.matched == [] do %>
                <div class="p-6 text-center text-gray-400 text-sm">No matched payments</div>
              <% else %>
                <div class="divide-y divide-gray-50">
                  <%= for payment <- @reconciliation.matched do %>
                    <div class="px-4 py-3 flex items-center justify-between">
                      <div>
                        <p class="text-sm font-medium text-gray-900">
                          Clover Order: {get_in(payment, ["order", "id"]) || "—"}
                        </p>
                        <p class="text-xs text-gray-500 font-mono">
                          ID: {payment["id"]}
                        </p>
                      </div>
                      <div class="text-right">
                        <p class="text-sm font-semibold text-gray-900">
                          ${format_cents(payment["amount"])}
                        </p>
                        <%= if payment["tipAmount"] && payment["tipAmount"] > 0 do %>
                          <p class="text-xs text-gray-400">
                            +${format_cents(payment["tipAmount"])} tip
                          </p>
                        <% end %>
                        <span class="inline-block text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full mt-1">
                          Matched
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Unmatched Payments --%>
            <div class="bg-white rounded-xl border border-gray-200">
              <div class="px-4 py-3 border-b border-gray-100">
                <h3 class="font-semibold text-gray-800">
                  Unmatched Clover Payments ({length(@reconciliation.unmatched)})
                </h3>
              </div>
              <%= if @reconciliation.unmatched == [] do %>
                <div class="p-6 text-center text-gray-400 text-sm">
                  ✅ All Clover payments are matched to orders
                </div>
              <% else %>
                <div class="divide-y divide-gray-50">
                  <%= for payment <- @reconciliation.unmatched do %>
                    <div class="px-4 py-3 flex items-center justify-between">
                      <div>
                        <p class="text-sm font-medium text-gray-900">
                          Clover Order: {get_in(payment, ["order", "id"]) || "—"}
                        </p>
                        <p class="text-xs text-gray-500 font-mono">
                          ID: {payment["id"]}
                        </p>
                      </div>
                      <div class="text-right">
                        <p class="text-sm font-semibold text-gray-900">
                          ${format_cents(payment["amount"])}
                        </p>
                        <span class="inline-block text-xs bg-orange-100 text-orange-700 px-2 py-0.5 rounded-full mt-1">
                          Unmatched
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="text-center py-12 text-gray-400">
              <p>Loading reconciliation data...</p>
            </div>
          <% end %>
        <% end %>
      </main>
    </div>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────

  defp format_cents(nil), do: "0.00"
  defp format_cents(0), do: "0.00"

  defp format_cents(cents) when is_integer(cents),
    do: :erlang.float_to_binary(cents / 100, decimals: 2)

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

  defp authorize(user) do
    if user.role in ~w(owner) do
      case user.restaurant_id && Tenancy.get_restaurant(user.restaurant_id) do
        nil -> {:error, :unauthorized}
        restaurant -> {:ok, restaurant}
      end
    else
      {:error, :unauthorized}
    end
  end
end
