defmodule RestaurantDashWeb.CheckoutLive do
  @moduledoc """
  Guest checkout flow — 3 steps:
  1. Delivery details (name, phone, email, address)
  2. Order review (full summary with totals)
  3. Place order (creates Order + OrderItems)

  No authentication required. Cart is loaded from the session-scoped ETS store.
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Cart, Orders, Tenancy}
  alias RestaurantDashWeb.CartHelpers

  # ─── Mount ───────────────────────────────────────────────────────────────────

  @impl true
  def mount(params, session, socket) do
    restaurant =
      case session["current_restaurant"] do
        %Tenancy.Restaurant{} = r -> r
        _ -> resolve_from_params(params)
      end

    socket =
      socket
      |> assign(:restaurant, restaurant)
      |> assign(:step, :delivery)
      |> assign(:form_data, %{
        "customer_name" => "",
        "customer_email" => "",
        "customer_phone" => "",
        "delivery_address" => ""
      })
      |> assign(:errors, %{})
      |> assign(:placing_order, false)
      |> CartHelpers.mount_cart(session, restaurant && restaurant.id)

    {:ok, socket}
  end

  # ─── Events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("update-field", %{"field" => field, "value" => value}, socket) do
    form_data = Map.put(socket.assigns.form_data, field, value)
    {:noreply, assign(socket, :form_data, form_data)}
  end

  @impl true
  def handle_event("next-step", _params, socket) do
    case socket.assigns.step do
      :delivery ->
        case validate_delivery(socket.assigns.form_data) do
          {:ok, _} ->
            {:noreply, assign(socket, step: :review, errors: %{})}

          {:error, errors} ->
            {:noreply, assign(socket, :errors, errors)}
        end

      :review ->
        {:noreply, assign(socket, :step, :confirm)}

      :confirm ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev-step", _params, socket) do
    new_step =
      case socket.assigns.step do
        :review -> :delivery
        :confirm -> :review
        _ -> :delivery
      end

    {:noreply, assign(socket, :step, new_step)}
  end

  @impl true
  def handle_event("place-order", _params, socket) do
    cart = socket.assigns.cart
    form_data = socket.assigns.form_data
    restaurant = socket.assigns.restaurant

    if Cart.empty?(cart) or is_nil(restaurant) do
      {:noreply, put_flash(socket, :error, "Your cart is empty.")}
    else
      socket = assign(socket, :placing_order, true)

      attrs = %{
        customer_name: form_data["customer_name"],
        customer_email: form_data["customer_email"],
        customer_phone: form_data["customer_phone"],
        delivery_address: form_data["delivery_address"],
        restaurant_id: restaurant.id
      }

      case Orders.create_order_from_cart(cart, attrs) do
        {:ok, order} ->
          # Schedule lifecycle worker
          maybe_schedule_lifecycle(order)

          # Clear the cart
          socket = CartHelpers.clear_cart(socket)

          {:noreply,
           socket
           |> put_flash(:info, "Order placed! Tracking your order now.")
           |> redirect(to: "/orders/#{order.id}/track")}

        {:error, changeset} ->
          errors = errors_from_changeset(changeset)

          {:noreply,
           socket
           |> assign(:placing_order, false)
           |> assign(:step, :delivery)
           |> assign(:errors, errors)
           |> put_flash(:error, "Please fix the errors below.")}
      end
    end
  end

  @impl true
  def handle_event("toggle-cart", _params, socket) do
    {:noreply, assign(socket, :cart_drawer_open, !socket.assigns.cart_drawer_open)}
  end

  @impl true
  def handle_event("close-cart", _params, socket) do
    {:noreply, assign(socket, :cart_drawer_open, false)}
  end

  # ─── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50" id="checkout-page">
      <%!-- Header --%>
      <header
        class="text-white px-6 py-4"
        style={"background-color: #{if @restaurant, do: @restaurant.primary_color, else: "#E63946"}"}
      >
        <div class="max-w-2xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-3">
            <%= if @restaurant do %>
              <a
                href={"/menu?restaurant_slug=#{@restaurant.slug}"}
                class="text-white/80 hover:text-white text-sm"
              >
                ← Menu
              </a>
              <span class="text-white/40">|</span>
              <span class="font-semibold">{@restaurant.name}</span>
            <% else %>
              <span class="font-semibold">Checkout</span>
            <% end %>
          </div>
          <span class="text-sm text-white/70">🔒 Secure Checkout</span>
        </div>
      </header>

      <%= if is_nil(@restaurant) or Cart.empty?(@cart) do %>
        <div class="flex items-center justify-center min-h-[60vh]">
          <div class="text-center">
            <p class="text-5xl mb-4">🛒</p>
            <p class="text-xl font-bold text-gray-800">Your cart is empty</p>
            <p class="text-gray-500 mt-2">Add some items before checking out</p>
            <%= if @restaurant do %>
              <a
                href={"/menu?restaurant_slug=#{@restaurant.slug}"}
                class="mt-4 inline-block font-medium text-white px-6 py-3 rounded-xl"
                style={"background-color: #{@restaurant.primary_color}"}
              >
                Browse Menu
              </a>
            <% end %>
          </div>
        </div>
      <% else %>
        <main class="max-w-2xl mx-auto px-6 py-8">
          <%!-- Step Indicator --%>
          <.step_indicator step={@step} />

          <%!-- Step Content --%>
          <%= case @step do %>
            <% :delivery -> %>
              <.delivery_form form_data={@form_data} errors={@errors} />
            <% :review -> %>
              <.order_review cart={@cart} form_data={@form_data} restaurant={@restaurant} />
            <% :confirm -> %>
              <.order_confirm
                cart={@cart}
                form_data={@form_data}
                restaurant={@restaurant}
                placing_order={@placing_order}
              />
          <% end %>
        </main>
      <% end %>
    </div>
    """
  end

  # ─── Components ───────────────────────────────────────────────────────────────

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center justify-center mb-8">
      <%= for {step, label, idx} <- [{:delivery, "Delivery", 1}, {:review, "Review", 2}, {:confirm, "Place Order", 3}] do %>
        <div class="flex items-center">
          <div class={"flex items-center justify-center w-8 h-8 rounded-full text-sm font-bold #{step_class(@step, step)}"}>
            {idx}
          </div>
          <span class={"ml-2 text-sm font-medium #{if @step == step, do: "text-gray-900", else: "text-gray-400"}"}>
            {label}
          </span>
          <%= unless step == :confirm do %>
            <div class="w-12 h-0.5 bg-gray-200 mx-3" />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp step_class(current, step) do
    steps = [:delivery, :review, :confirm]
    current_idx = Enum.find_index(steps, &(&1 == current))
    step_idx = Enum.find_index(steps, &(&1 == step))

    cond do
      step == current -> "bg-blue-600 text-white"
      step_idx < current_idx -> "bg-green-500 text-white"
      true -> "bg-gray-200 text-gray-500"
    end
  end

  defp delivery_form(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
      <h2 class="text-xl font-bold text-gray-900 mb-6">Delivery Details</h2>

      <div class="space-y-4">
        <.field
          label="Full Name"
          field="customer_name"
          value={@form_data["customer_name"]}
          error={@errors["customer_name"]}
          placeholder="Jane Doe"
          type="text"
        />
        <.field
          label="Email"
          field="customer_email"
          value={@form_data["customer_email"]}
          error={@errors["customer_email"]}
          placeholder="jane@example.com"
          type="email"
        />
        <.field
          label="Phone"
          field="customer_phone"
          value={@form_data["customer_phone"]}
          error={@errors["customer_phone"]}
          placeholder="(555) 123-4567"
          type="tel"
        />
        <.field
          label="Delivery Address"
          field="delivery_address"
          value={@form_data["delivery_address"]}
          error={@errors["delivery_address"]}
          placeholder="123 Main St, San Francisco, CA 94103"
          type="text"
        />
      </div>

      <button
        phx-click="next-step"
        class="w-full mt-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition-colors"
      >
        Continue to Review →
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: ""
  attr :error, :string, default: nil
  attr :placeholder, :string, default: ""
  attr :type, :string, default: "text"

  defp field(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">{@label}</label>
      <input
        type={@type}
        value={@value}
        placeholder={@placeholder}
        phx-change="update-field"
        phx-value-field={@field}
        name={@field}
        class={"w-full px-4 py-3 border rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 #{if @error, do: "border-red-400 bg-red-50", else: "border-gray-300"}"}
      />
      <%= if @error do %>
        <p class="text-red-500 text-xs mt-1">{@error}</p>
      <% end %>
    </div>
    """
  end

  defp order_review(assigns) do
    ~H"""
    <% totals = Cart.calculate_totals(@cart) %>
    <div class="space-y-4">
      <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
        <h2 class="text-xl font-bold text-gray-900 mb-4">Order Summary</h2>
        <div class="space-y-3">
          <%= for item <- @cart.items do %>
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-gray-700 bg-gray-100 rounded px-1.5 py-0.5">
                    ×{item.quantity}
                  </span>
                  <span class="text-sm font-medium text-gray-900">{item.name}</span>
                </div>
                <%= if length(item.modifier_names) > 0 do %>
                  <p class="text-xs text-gray-500 mt-0.5 ml-7">
                    {Enum.map_join(item.modifier_names, ", ", fn
                      {name, _} -> name
                      name -> name
                    end)}
                  </p>
                <% end %>
              </div>
              <span class="text-sm font-semibold text-gray-900 flex-shrink-0">
                {format_price(item.line_total)}
              </span>
            </div>
          <% end %>
        </div>

        <div class="mt-4 pt-4 border-t border-gray-100 space-y-2">
          <div class="flex justify-between text-sm text-gray-600">
            <span>Subtotal</span><span>{format_price(totals.subtotal)}</span>
          </div>
          <div class="flex justify-between text-sm text-gray-600">
            <span>Tax</span><span>{format_price(totals.tax)}</span>
          </div>
          <div class="flex justify-between text-sm text-gray-600">
            <span>Delivery</span><span>{format_price(totals.delivery_fee)}</span>
          </div>
          <div class="flex justify-between font-bold text-gray-900 pt-2 border-t border-gray-100">
            <span>Total</span><span>{format_price(totals.total)}</span>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
        <h3 class="font-semibold text-gray-900 mb-3">Delivering to</h3>
        <p class="text-sm text-gray-700">{@form_data["customer_name"]}</p>
        <p class="text-sm text-gray-500">{@form_data["delivery_address"]}</p>
        <p class="text-sm text-gray-500">
          {@form_data["customer_phone"]} · {@form_data["customer_email"]}
        </p>
      </div>

      <div class="flex gap-3">
        <button
          phx-click="prev-step"
          class="flex-1 py-3 border border-gray-300 hover:bg-gray-50 text-gray-700 font-semibold rounded-xl transition-colors"
        >
          ← Back
        </button>
        <button
          phx-click="next-step"
          class="flex-1 py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition-colors"
        >
          Looks Good →
        </button>
      </div>
    </div>
    """
  end

  defp order_confirm(assigns) do
    ~H"""
    <% totals = Cart.calculate_totals(@cart) %>
    <div class="space-y-4">
      <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm text-center">
        <span class="text-4xl">🍕</span>
        <h2 class="text-xl font-bold text-gray-900 mt-3">Ready to order?</h2>
        <p class="text-gray-500 text-sm mt-1">
          Your order from {@restaurant.name} will be placed
        </p>
        <p class="text-2xl font-bold mt-3" style={"color: #{@restaurant.primary_color}"}>
          {format_price(totals.total)}
        </p>
        <p class="text-xs text-gray-400 mt-1">
          incl. tax + delivery
        </p>
      </div>

      <div class="flex gap-3">
        <button
          phx-click="prev-step"
          class="flex-1 py-3 border border-gray-300 hover:bg-gray-50 text-gray-700 font-semibold rounded-xl transition-colors"
          disabled={@placing_order}
        >
          ← Back
        </button>
        <button
          phx-click="place-order"
          disabled={@placing_order}
          class={"flex-1 py-3 text-white font-semibold rounded-xl transition-colors #{if @placing_order, do: "opacity-60 cursor-not-allowed", else: "hover:opacity-90"}"}
          style={"background-color: #{@restaurant.primary_color}"}
        >
          <%= if @placing_order do %>
            Placing Order...
          <% else %>
            Place Order 🎉
          <% end %>
        </button>
      </div>
    </div>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────────

  defp validate_delivery(form_data) do
    errors = %{}

    errors =
      if blank?(form_data["customer_name"]),
        do: Map.put(errors, "customer_name", "Name is required"),
        else: errors

    errors =
      if blank?(form_data["customer_email"]),
        do: Map.put(errors, "customer_email", "Email is required"),
        else:
          if(valid_email?(form_data["customer_email"]),
            do: errors,
            else: Map.put(errors, "customer_email", "Enter a valid email")
          )

    errors =
      if blank?(form_data["customer_phone"]),
        do: Map.put(errors, "customer_phone", "Phone is required"),
        else: errors

    errors =
      if blank?(form_data["delivery_address"]),
        do: Map.put(errors, "delivery_address", "Delivery address is required"),
        else: errors

    if map_size(errors) == 0, do: {:ok, form_data}, else: {:error, errors}
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""

  defp valid_email?(email) when is_binary(email) do
    String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
  end

  defp valid_email?(_), do: false

  defp errors_from_changeset(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> {to_string(k), Enum.join(v, ", ")} end)
    |> Map.new()
  end

  defp maybe_schedule_lifecycle(order) do
    try do
      RestaurantDash.Workers.OrderLifecycleWorker.schedule_for(order)
    rescue
      _ -> :ok
    end
  end

  defp resolve_from_params(%{"restaurant_slug" => slug}) when is_binary(slug) do
    Tenancy.get_restaurant_by_slug(slug)
  end

  defp resolve_from_params(_), do: nil

  defp format_price(nil), do: "$0.00"

  defp format_price(price_cents) when is_integer(price_cents) do
    dollars = div(price_cents, 100)
    cents = rem(price_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end
end
