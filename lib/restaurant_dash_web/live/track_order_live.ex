defmodule RestaurantDashWeb.TrackOrderLive do
  @moduledoc """
  Customer-facing order tracking page.

  - No login required — accessed via /orders/:id/track
  - Real-time status updates via PubSub
  - Shows order timeline: Placed → Preparing → Out for Delivery → Delivered
  - Shows order summary with all items
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Orders, Tenancy, Drivers}

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
         |> assign(:not_found, true)
         |> assign(:driver_lat, nil)
         |> assign(:driver_lng, nil)
         |> assign(:driver_profile, nil)
         |> assign(:restaurant, nil)
         |> assign(:timeline_steps, @timeline_steps)
         |> assign(:rating_submitted, false)}

      order ->
        if connected?(socket) do
          Orders.subscribe(order.id)
        end

        restaurant = order.restaurant_id && Tenancy.get_restaurant(order.restaurant_id)
        driver_profile = order.driver_id && Drivers.get_profile_by_user_id(order.driver_id)

        # Seed driver location from ETS cache if available
        driver_loc = get_driver_location(order)

        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:restaurant, restaurant)
         |> assign(:driver_profile, driver_profile)
         |> assign(:not_found, false)
         |> assign(:timeline_steps, @timeline_steps)
         |> assign(:driver_lat, elem(driver_loc, 0))
         |> assign(:driver_lng, elem(driver_loc, 1))
         |> assign(:rating_submitted, order.driver_rating != nil)}
    end
  end

  # ─── Events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("submit_rating", %{"rating" => rating, "comment" => comment}, socket) do
    order = socket.assigns.order
    rating_int = String.to_integer(rating)

    case Orders.submit_driver_rating(order, rating_int, comment) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:rating_submitted, true)
         |> put_flash(:info, "Thank you for your feedback!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to submit rating.")}
    end
  end

  @impl true
  def handle_event("submit_restaurant_review", %{"rating" => rating} = params, socket) do
    order = socket.assigns.order
    rating_int = String.to_integer(rating)
    review_text = Map.get(params, "review", "")

    case Orders.submit_restaurant_review(order, rating_int, review_text) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:order, updated)
         |> put_flash(:info, "Thank you for reviewing the restaurant!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to submit review.")}
    end
  end

  @impl true
  def handle_info({:order_updated, order}, socket) do
    if order.id == socket.assigns.order.id do
      # Reload with order_items
      updated = Orders.get_order_with_items!(order.id)
      driver_profile = updated.driver_id && Drivers.get_profile_by_user_id(updated.driver_id)
      driver_loc = get_driver_location(updated)

      {:noreply,
       socket
       |> assign(:order, updated)
       |> assign(:driver_profile, driver_profile)
       |> assign(:driver_lat, elem(driver_loc, 0))
       |> assign(:driver_lng, elem(driver_loc, 1))}
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

          <%!-- Driver Live Map (shown when driver is en route) --%>
          <%= if @order.status in ["assigned", "picked_up", "out_for_delivery"] && @order.driver_id do %>
            <div class="bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden">
              <div class="px-6 pt-4 pb-2">
                <h3 class="font-semibold text-gray-900">Driver Location</h3>
                <p class="text-xs text-gray-500 mt-0.5">Updates every 10 seconds</p>
              </div>
              <div
                id={"driver-map-#{@order.id}"}
                phx-hook="DriverTrackingMap"
                phx-update="ignore"
                data-order-id={@order.id}
                data-lat={@driver_lat || 37.7749}
                data-lng={@driver_lng || -122.4194}
                data-has-driver={to_string(@driver_lat != nil)}
                style="height: 280px; width: 100%;"
              />
            </div>
          <% end %>

          <%!-- Driver Info Card (shown when driver assigned, no phone for privacy) --%>
          <%= if @order.driver_id && @order.status in ["assigned", "picked_up", "out_for_delivery"] do %>
            <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
              <h3 class="font-semibold text-gray-900 mb-4">Your Driver</h3>
              <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-full bg-blue-100 flex items-center justify-center text-2xl">
                  🚗
                </div>
                <div class="flex-1">
                  <%= if @driver_profile do %>
                    <p class="font-medium text-gray-900">
                      {vehicle_type_label(@driver_profile.vehicle_type)}
                    </p>
                    <%= if @driver_profile.license_plate do %>
                      <p class="text-sm text-gray-500">{@driver_profile.license_plate}</p>
                    <% end %>
                  <% else %>
                    <p class="font-medium text-gray-900">Driver En Route</p>
                    <p class="text-sm text-gray-500">Your driver is on the way</p>
                  <% end %>
                </div>
                <div class="text-right">
                  <div class="text-xs text-gray-400 uppercase tracking-wide">Status</div>
                  <div class="text-sm font-semibold text-blue-600 mt-0.5">
                    {humanize_delivery_status(@order.status)}
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Restaurant Info --%>
          <%= if @restaurant do %>
            <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
              <h3 class="font-semibold text-gray-900 mb-3">Restaurant</h3>
              <p class="text-sm font-medium text-gray-900">{@restaurant.name}</p>
              <%= if @restaurant.address do %>
                <p class="text-sm text-gray-500 mt-1">
                  {@restaurant.address}
                  <%= if @restaurant.city do %>
                    , {@restaurant.city}
                  <% end %>
                </p>
              <% end %>
              <%= if @restaurant.phone do %>
                <a
                  href={"tel:#{@restaurant.phone}"}
                  class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-700 mt-2"
                >
                  📞 {@restaurant.phone}
                </a>
              <% end %>
            </div>
          <% end %>

          <%!-- Need Help? --%>
          <div class="bg-gray-50 rounded-2xl border border-gray-200 p-6 text-center">
            <p class="text-sm font-medium text-gray-700 mb-3">Having an issue with your order?</p>
            <%= if @restaurant && @restaurant.phone do %>
              <a
                href={"tel:#{@restaurant.phone}"}
                class="inline-flex items-center gap-2 bg-white border border-gray-300 text-gray-700 rounded-xl px-5 py-2.5 text-sm font-medium hover:bg-gray-50 transition shadow-sm"
              >
                📞 Call Restaurant
              </a>
            <% else %>
              <p class="text-sm text-gray-500">Please contact the restaurant directly.</p>
            <% end %>
          </div>

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

          <%!-- Restaurant Review (shown after delivery) --%>
          <%= if @order.status == "delivered" do %>
            <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
              <%= if @order.restaurant_rating do %>
                <div class="text-center">
                  <p class="text-2xl mb-1">🌟</p>
                  <p class="font-semibold text-gray-900">Thanks for reviewing the restaurant!</p>
                </div>
              <% else %>
                <h3 class="font-semibold text-gray-900 mb-3">Rate the Restaurant</h3>
                <.form for={%{}} as={:review_form} phx-submit="submit_restaurant_review">
                  <div class="flex justify-center gap-2 mb-3">
                    <%= for star <- 1..5 do %>
                      <label class="cursor-pointer text-3xl">
                        <input type="radio" name="rating" value={star} class="sr-only" required />
                        <span class="hover:scale-110 transition-transform inline-block">⭐</span>
                      </label>
                    <% end %>
                  </div>
                  <textarea
                    name="review"
                    placeholder="Tell us about your experience (optional)"
                    class="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm resize-none"
                    rows="2"
                  />
                  <button
                    type="submit"
                    class="mt-3 w-full py-2.5 bg-indigo-600 text-white rounded-xl text-sm font-semibold hover:bg-indigo-700"
                  >
                    Submit Review
                  </button>
                </.form>
              <% end %>
            </div>
          <% end %>

          <%!-- Driver Rating (shown after delivery) --%>
          <%= if @order.status == "delivered" && @order.driver_id do %>
            <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
              <%= if @rating_submitted or @order.driver_rating do %>
                <div class="text-center">
                  <p class="text-2xl mb-1">⭐</p>
                  <p class="font-semibold text-gray-900">Thanks for your feedback!</p>
                  <p class="text-sm text-gray-500 mt-1">
                    You rated your driver {rating_stars(@order.driver_rating || 5)}
                  </p>
                </div>
              <% else %>
                <h3 class="font-semibold text-gray-900 mb-4">Rate Your Driver</h3>
                <.form for={%{}} as={:rating_form} phx-submit="submit_rating">
                  <div class="flex justify-center gap-2 mb-4">
                    <%= for star <- 1..5 do %>
                      <label class="cursor-pointer text-3xl">
                        <input
                          type="radio"
                          name="rating"
                          value={star}
                          class="sr-only"
                          required
                        />
                        <span class="hover:scale-110 transition-transform inline-block">⭐</span>
                      </label>
                    <% end %>
                  </div>
                  <textarea
                    name="comment"
                    placeholder="Any comments? (optional)"
                    class="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm resize-none focus:ring-2 focus:ring-blue-400 focus:outline-none"
                    rows="2"
                  />
                  <button
                    type="submit"
                    class="mt-3 w-full py-2.5 bg-blue-600 text-white rounded-xl text-sm font-semibold hover:bg-blue-700 transition"
                  >
                    Submit Rating
                  </button>
                </.form>
              <% end %>
            </div>
          <% end %>
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

  defp vehicle_type_label("car"), do: "Car Delivery"
  defp vehicle_type_label("bike"), do: "Bike Delivery"
  defp vehicle_type_label("motorcycle"), do: "Motorcycle Delivery"
  defp vehicle_type_label("van"), do: "Van Delivery"
  defp vehicle_type_label(_), do: "Driver"

  defp humanize_delivery_status("assigned"), do: "Heading to pickup"
  defp humanize_delivery_status("picked_up"), do: "Order picked up"
  defp humanize_delivery_status("out_for_delivery"), do: "On the way!"

  defp humanize_delivery_status(status),
    do: String.replace(status, "_", " ") |> String.capitalize()

  defp get_driver_location(%{driver_id: nil}), do: {nil, nil}

  defp get_driver_location(%{driver_id: driver_id}) when not is_nil(driver_id) do
    case RestaurantDash.Drivers.LocationCache.get(driver_id) do
      {:ok, {lat, lng}} -> {lat, lng}
      :not_found -> {nil, nil}
    end
  end

  defp rating_stars(rating) when is_integer(rating) do
    String.duplicate("⭐", rating)
  end

  defp rating_stars(_), do: ""

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
