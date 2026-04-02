defmodule RestaurantDashWeb.TrackOrderLive do
  @moduledoc """
  Customer-facing order tracking page.

  - No login required — accessed via /orders/:id/track
  - Real-time status updates via PubSub
  - Shows order timeline: Placed → Preparing → Out for Delivery → Delivered
  - Shows order summary with all items
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Orders, Tenancy}

  @timeline_steps [
    {"new", "Order Placed", "✅", "We received your order!"},
    {"preparing", "Preparing", "👨‍🍳", "The kitchen is making your order"},
    {"assigned", "Driver Assigned", "🚗", "A driver is on the way to pick up your order"},
    {"picked_up", "Picked Up", "🛵", "Your order has been picked up!"},
    {"out_for_delivery", "Out for Delivery", "🛵", "Your order is on the way!"},
    {"delivered", "Delivered", "🎉", "Enjoy your meal!"}
  ]

  # ─── Mount ───────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Orders.get_order_with_items(id) do
      nil ->
        {:ok,
         socket
         |> assign(:order, nil)
         |> assign(:not_found, true)}

      order ->
        if connected?(socket) do
          Orders.subscribe(order.id)
        end

        restaurant = order.restaurant_id && Tenancy.get_restaurant(order.restaurant_id)

        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:restaurant, restaurant)
         |> assign(:not_found, false)
         |> assign(:timeline_steps, @timeline_steps)}
    end
  end

  # ─── Events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:order_updated, order}, socket) do
    if order.id == socket.assigns.order.id do
      # Reload with order_items
      updated = Orders.get_order_with_items!(order.id)
      {:noreply, assign(socket, :order, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ─── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @not_found do %>
        <div class="flex items-center justify-center min-h-screen">
          <div class="text-center">
            <p class="text-5xl mb-4">🔍</p>
            <p class="text-xl font-bold text-gray-800">Order not found</p>
            <p class="text-gray-500 mt-2">This order doesn't exist or has been removed.</p>
            <a href="/" class="mt-4 inline-block text-blue-600 hover:underline">Go home</a>
          </div>
        </div>
      <% else %>
        <%!-- Header --%>
        <header
          class="text-white px-6 py-4"
          style={"background-color: #{if @restaurant, do: @restaurant.primary_color, else: "#E63946"}"}
        >
          <div class="max-w-2xl mx-auto">
            <h1 class="text-xl font-bold">Track Your Order</h1>
            <p class="text-white/70 text-sm">Order #{@order.id}</p>
          </div>
        </header>

        <main class="max-w-2xl mx-auto px-6 py-8 space-y-6">
          <%!-- Status Banner --%>
          <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm text-center">
            <% current = current_step(@order.status, @timeline_steps) %>
            <span class="text-4xl">{elem(current, 2)}</span>
            <h2 class="text-xl font-bold text-gray-900 mt-3">{elem(current, 1)}</h2>
            <p class="text-gray-500 text-sm mt-1">{elem(current, 3)}</p>

            <%!-- Estimated time --%>
            <%= if @order.status != "delivered" do %>
              <div class="mt-4 inline-flex items-center gap-2 bg-gray-50 rounded-full px-4 py-2">
                <span class="text-sm text-gray-600">
                  Estimated: <strong>{estimated_time(@order)}</strong>
                </span>
              </div>
            <% end %>
          </div>

          <%!-- Timeline --%>
          <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
            <h3 class="font-semibold text-gray-900 mb-4">Order Progress</h3>
            <div class="space-y-0">
              <%= for {status, label, icon, _desc} <- @timeline_steps do %>
                <% state = step_state(@order.status, status, @timeline_steps) %>
                <div class="flex items-start gap-4">
                  <div class="flex flex-col items-center">
                    <div class={"w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold #{timeline_dot_class(state)}"}>
                      <%= if state == :done or state == :active do %>
                        {icon}
                      <% else %>
                        <span class="w-2 h-2 rounded-full bg-gray-300" />
                      <% end %>
                    </div>
                    <%= unless status == "delivered" do %>
                      <div class={"w-0.5 h-8 #{if state == :done, do: "bg-green-400", else: "bg-gray-200"}"} />
                    <% end %>
                  </div>
                  <div class="pt-1 pb-6">
                    <p class={"text-sm font-medium #{if state == :pending, do: "text-gray-400", else: "text-gray-900"}"}>
                      {label}
                    </p>
                    <%= if state == :active do %>
                      <p class="text-xs text-blue-600 mt-0.5 animate-pulse">In progress...</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Order Items --%>
          <%= if @order.order_items && length(@order.order_items) > 0 do %>
            <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
              <h3 class="font-semibold text-gray-900 mb-4">Your Order</h3>
              <div class="space-y-3">
                <%= for item <- @order.order_items do %>
                  <div class="flex items-start justify-between gap-4">
                    <div class="flex-1">
                      <div class="flex items-center gap-2">
                        <span class="text-xs font-medium text-gray-500 bg-gray-100 rounded px-1.5 py-0.5">
                          ×{item.quantity}
                        </span>
                        <span class="text-sm font-medium text-gray-900">{item.name}</span>
                      </div>
                      <%= if item.modifiers_json && item.modifiers_json != "[]" do %>
                        <% mods = decode_modifiers(item.modifiers_json) %>
                        <%= unless mods == [] do %>
                          <p class="text-xs text-gray-500 mt-0.5 ml-7">
                            {Enum.map_join(mods, ", ", & &1["name"])}
                          </p>
                        <% end %>
                      <% end %>
                    </div>
                    <span class="text-sm font-semibold text-gray-900">
                      {format_price(item.line_total)}
                    </span>
                  </div>
                <% end %>
              </div>

              <%!-- Totals --%>
              <%= if @order.total_amount > 0 do %>
                <div class="mt-4 pt-4 border-t border-gray-100 space-y-1">
                  <div class="flex justify-between text-sm text-gray-500">
                    <span>Subtotal</span><span>{format_price(@order.subtotal)}</span>
                  </div>
                  <div class="flex justify-between text-sm text-gray-500">
                    <span>Tax</span><span>{format_price(@order.tax_amount)}</span>
                  </div>
                  <div class="flex justify-between text-sm text-gray-500">
                    <span>Delivery</span><span>{format_price(@order.delivery_fee)}</span>
                  </div>
                  <div class="flex justify-between font-bold text-gray-900 pt-2 border-t border-gray-100">
                    <span>Total</span><span>{format_price(@order.total_amount)}</span>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- Delivery info --%>
          <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
            <h3 class="font-semibold text-gray-900 mb-3">Delivery Details</h3>
            <p class="text-sm text-gray-700 font-medium">{@order.customer_name}</p>
            <%= if @order.delivery_address do %>
              <p class="text-sm text-gray-500">{@order.delivery_address}</p>
            <% end %>
            <%= if @order.customer_phone do %>
              <p class="text-sm text-gray-500">{@order.customer_phone}</p>
            <% end %>
          </div>
        </main>
      <% end %>
    </div>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────────

  defp current_step(status, timeline) do
    Enum.find(timeline, hd(timeline), fn {s, _, _, _} -> s == status end)
  end

  defp step_state(current_status, step_status, timeline) do
    statuses = Enum.map(timeline, &elem(&1, 0))
    current_idx = Enum.find_index(statuses, &(&1 == current_status)) || 0
    step_idx = Enum.find_index(statuses, &(&1 == step_status)) || 0

    cond do
      step_idx < current_idx -> :done
      step_idx == current_idx -> :active
      true -> :pending
    end
  end

  defp timeline_dot_class(:done), do: "bg-green-100 text-green-600"
  defp timeline_dot_class(:active), do: "bg-blue-100 text-blue-600 ring-2 ring-blue-300"
  defp timeline_dot_class(:pending), do: "bg-gray-100 text-gray-400"

  defp estimated_time(order) do
    case order.status do
      "new" -> "30-45 min"
      "preparing" -> "20-30 min"
      "out_for_delivery" -> "10-15 min"
      _ -> "—"
    end
  end

  defp decode_modifiers(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp format_price(nil), do: "$0.00"
  defp format_price(0), do: "$0.00"

  defp format_price(price_cents) when is_integer(price_cents) do
    dollars = div(price_cents, 100)
    cents = rem(price_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end
end
