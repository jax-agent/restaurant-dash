defmodule RestaurantDashWeb.CheckoutLive do
  @moduledoc """
  Guest checkout flow — 4 steps:
  1. Delivery details (name, phone, email, address)
  2. Order review (full summary with item list)
  3. Payment (Stripe Elements or Pay on Delivery / mock demo)
  4. Confirm & place order

  No authentication required. Cart is loaded from the session-scoped ETS store.
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Cart, Orders, Tenancy, Payments}
  alias RestaurantDashWeb.CartHelpers

  # ─── Mount ───────────────────────────────────────────────────────────────────

  @impl true
  def mount(params, session, socket) do
    restaurant =
      case session["current_restaurant"] do
        %Tenancy.Restaurant{} = r -> r
        _ -> resolve_from_params(params)
      end

    # Re-load restaurant to get stripe_account_id
    restaurant =
      if restaurant do
        Tenancy.get_restaurant!(restaurant.id)
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
      |> assign(:payment_method, "cash")
      |> assign(:payment_intent_id, nil)
      |> assign(:tip_amount, 0)
      |> assign(:tip_option, "0")
      |> assign(:custom_tip, "")
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
  def handle_event("select-tip", %{"percent" => percent_str}, socket) do
    case Integer.parse(percent_str) do
      {percent, ""} ->
        subtotal = Cart.calculate_totals(socket.assigns.cart).subtotal
        tip = Payments.calculate_tip(subtotal, percent)

        {:noreply,
         socket
         |> assign(:tip_option, percent_str)
         |> assign(:tip_amount, tip)
         |> assign(:custom_tip, "")}

      _ ->
        {:noreply, assign(socket, :tip_option, "custom")}
    end
  end

  @impl true
  def handle_event("update-custom-tip", %{"value" => value}, socket) do
    tip =
      case Float.parse(value) do
        {dollars, _} -> round(dollars * 100)
        :error -> 0
      end

    {:noreply,
     socket
     |> assign(:custom_tip, value)
     |> assign(:tip_amount, max(0, tip))}
  end

  @impl true
  def handle_event("select-payment-method", %{"method" => method}, socket) do
    {:noreply, assign(socket, :payment_method, method)}
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
        {:noreply, assign(socket, :step, :payment)}

      :payment ->
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
        :payment -> :review
        :confirm -> :payment
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
      tip = socket.assigns.tip_amount

      # Create PaymentIntent if we're going through Stripe path
      {payment_intent_id, payment_status} =
        if socket.assigns.payment_method == "stripe" and
             Payments.stripe_connected?(restaurant) do
          order_stub = %{
            subtotal: Cart.calculate_totals(cart).subtotal,
            tip_amount: tip,
            total_amount: Cart.calculate_totals(cart, tip: tip).total,
            tax_amount: Cart.calculate_totals(cart).tax,
            delivery_fee: Cart.calculate_totals(cart).delivery_fee
          }

          case Payments.create_payment_intent(order_stub,
                 stripe_account_id: restaurant.stripe_account_id
               ) do
            {:ok, result} -> {result.payment_intent_id, "pending"}
            {:error, _} -> {nil, "pending"}
          end
        else
          {nil, "pending"}
        end

      attrs = %{
        customer_name: form_data["customer_name"],
        customer_email: form_data["customer_email"],
        customer_phone: form_data["customer_phone"],
        delivery_address: form_data["delivery_address"],
        restaurant_id: restaurant.id,
        payment_intent_id: payment_intent_id,
        payment_status: payment_status
      }

      case Orders.create_order_from_cart(cart, attrs, tip: tip) do
        {:ok, order} ->
          maybe_schedule_lifecycle(order)
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
              <.order_review
                cart={@cart}
                form_data={@form_data}
                restaurant={@restaurant}
                tip_amount={@tip_amount}
                tip_option={@tip_option}
                custom_tip={@custom_tip}
              />
            <% :payment -> %>
              <.payment_step
                restaurant={@restaurant}
                payment_method={@payment_method}
                cart={@cart}
                tip_amount={@tip_amount}
              />
            <% :confirm -> %>
              <.order_confirm
                cart={@cart}
                form_data={@form_data}
                restaurant={@restaurant}
                placing_order={@placing_order}
                tip_amount={@tip_amount}
                payment_method={@payment_method}
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
      <%= for {step, label, idx} <- [
        {:delivery, "Delivery", 1},
        {:review, "Review", 2},
        {:payment, "Payment", 3},
        {:confirm, "Place Order", 4}
      ] do %>
        <div class="flex items-center">
          <div class={"flex items-center justify-center w-8 h-8 rounded-full text-sm font-bold #{step_class(@step, step)}"}>
            {idx}
          </div>
          <span class={"ml-2 text-sm font-medium #{if @step == step, do: "text-gray-900", else: "text-gray-400"}"}>
            {label}
          </span>
          <%= unless step == :confirm do %>
            <div class="w-8 h-0.5 bg-gray-200 mx-3" />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp step_class(current, step) do
    steps = [:delivery, :review, :payment, :confirm]
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
    <% totals = Cart.calculate_totals(@cart, tip: @tip_amount) %>
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
          <%= if @tip_amount > 0 do %>
            <div class="flex justify-between text-sm text-gray-600">
              <span>Tip</span><span>{format_price(@tip_amount)}</span>
            </div>
          <% end %>
          <div class="flex justify-between font-bold text-gray-900 pt-2 border-t border-gray-100">
            <span>Total</span><span>{format_price(totals.total)}</span>
          </div>
        </div>
      </div>

      <%!-- Tip Selection --%>
      <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
        <h3 class="font-semibold text-gray-900 mb-3">Add a Tip</h3>
        <p class="text-xs text-gray-500 mb-3">100% goes to your driver</p>
        <div class="flex gap-2 flex-wrap">
          <%= for {label, percent} <- Payments.tip_options() do %>
            <%= if percent == :custom do %>
              <button
                phx-click="select-tip"
                phx-value-percent="custom"
                class={"px-3 py-2 rounded-lg text-sm font-medium border transition-colors #{if @tip_option == "custom", do: "bg-blue-600 text-white border-blue-600", else: "border-gray-300 text-gray-700 hover:bg-gray-50"}"}
              >
                {label}
              </button>
            <% else %>
              <button
                phx-click="select-tip"
                phx-value-percent={percent}
                class={"px-3 py-2 rounded-lg text-sm font-medium border transition-colors #{if @tip_option == to_string(percent), do: "bg-blue-600 text-white border-blue-600", else: "border-gray-300 text-gray-700 hover:bg-gray-50"}"}
              >
                {label}
              </button>
            <% end %>
          <% end %>
        </div>
        <%= if @tip_option == "custom" do %>
          <div class="mt-3">
            <label class="block text-sm font-medium text-gray-700 mb-1">Custom tip amount</label>
            <div class="flex items-center">
              <span class="text-gray-500 text-sm mr-2">$</span>
              <input
                type="number"
                min="0"
                step="0.01"
                value={@custom_tip}
                phx-change="update-custom-tip"
                phx-value-field="custom_tip"
                placeholder="0.00"
                class="w-32 px-3 py-2 border border-gray-300 rounded-lg text-sm"
              />
            </div>
          </div>
        <% end %>
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
          Continue to Payment →
        </button>
      </div>
    </div>
    """
  end

  defp payment_step(assigns) do
    ~H"""
    <% totals = Cart.calculate_totals(@cart, tip: @tip_amount) %>
    <div class="space-y-4">
      <div class="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
        <h2 class="text-xl font-bold text-gray-900 mb-2">Payment</h2>
        <p class="text-sm text-gray-500 mb-6">
          Total: <strong class="text-gray-900">{format_price(totals.total)}</strong>
        </p>

        <%= if Payments.mock_mode?() do %>
          <div class="mb-4 p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
            <p class="text-xs font-medium text-yellow-700">
              🎭 Demo Mode — No real charges will be made
            </p>
          </div>
        <% end %>

        <%!-- Payment Method Options --%>
        <div class="space-y-3">
          <%= if Payments.stripe_connected?(@restaurant) do %>
            <%!-- Stripe option --%>
            <label class={"flex items-center gap-3 p-4 border-2 rounded-xl cursor-pointer transition-colors #{if @payment_method == "stripe", do: "border-blue-500 bg-blue-50", else: "border-gray-200 hover:border-gray-300"}"}>
              <input
                type="radio"
                name="payment_method"
                value="stripe"
                checked={@payment_method == "stripe"}
                phx-click="select-payment-method"
                phx-value-method="stripe"
                class="text-blue-600"
              />
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <span class="font-medium text-gray-900">Credit / Debit Card</span>
                  <span class="text-xs text-gray-400">via Stripe</span>
                </div>
                <p class="text-xs text-gray-500">Visa, Mastercard, Amex, Discover</p>
              </div>
              <span class="text-2xl">💳</span>
            </label>

            <%= if @payment_method == "stripe" do %>
              <div class="p-4 bg-gray-50 border border-gray-200 rounded-xl">
                <%= if Payments.mock_mode?() do %>
                  <%!-- Mock card form --%>
                  <p class="text-xs text-yellow-600 font-medium mb-3">
                    Demo card form — use any test values
                  </p>
                  <div class="space-y-3">
                    <div>
                      <label class="block text-xs font-medium text-gray-600 mb-1">
                        Card Number
                      </label>
                      <input
                        type="text"
                        placeholder="4242 4242 4242 4242"
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                      />
                    </div>
                    <div class="grid grid-cols-2 gap-3">
                      <div>
                        <label class="block text-xs font-medium text-gray-600 mb-1">
                          Expiry
                        </label>
                        <input
                          type="text"
                          placeholder="MM/YY"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                        />
                      </div>
                      <div>
                        <label class="block text-xs font-medium text-gray-600 mb-1">CVC</label>
                        <input
                          type="text"
                          placeholder="123"
                          class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                        />
                      </div>
                    </div>
                  </div>
                <% else %>
                  <%!-- Real Stripe Elements would be mounted here via JS hook --%>
                  <div id="stripe-payment-element" phx-update="ignore">
                    <p class="text-sm text-gray-500">Loading Stripe...</p>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>

          <%!-- Pay on Delivery option --%>
          <label class={"flex items-center gap-3 p-4 border-2 rounded-xl cursor-pointer transition-colors #{if @payment_method == "cash", do: "border-green-500 bg-green-50", else: "border-gray-200 hover:border-gray-300"}"}>
            <input
              type="radio"
              name="payment_method"
              value="cash"
              checked={@payment_method == "cash"}
              phx-click="select-payment-method"
              phx-value-method="cash"
              class="text-green-600"
            />
            <div class="flex-1">
              <span class="font-medium text-gray-900">Pay on Delivery</span>
              <p class="text-xs text-gray-500">Cash or card when delivered</p>
            </div>
            <span class="text-2xl">💵</span>
          </label>
        </div>
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
          Review Order →
        </button>
      </div>
    </div>
    """
  end

  defp order_confirm(assigns) do
    ~H"""
    <% totals = Cart.calculate_totals(@cart, tip: @tip_amount) %>
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
          incl. tax + delivery<%= if @tip_amount > 0, do: " + tip" %>
        </p>

        <div class="mt-4 p-3 bg-gray-50 rounded-xl text-sm text-gray-600">
          <span class="font-medium">Payment: </span>
          <%= if @payment_method == "stripe" do %>
            💳 Credit/Debit Card
          <% else %>
            💵 Pay on Delivery
          <% end %>
        </div>

        <%= if Payments.mock_mode?() do %>
          <div class="mt-3 p-2 bg-yellow-50 border border-yellow-200 rounded-lg">
            <p class="text-xs text-yellow-700">🎭 Demo Mode — No real charges</p>
          </div>
        <% end %>
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

  defp format_price(nil), do: "$0.00"

  defp format_price(price_cents) when is_integer(price_cents) do
    dollars = div(price_cents, 100)
    cents = rem(price_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end

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
end
