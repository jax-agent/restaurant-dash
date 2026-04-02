defmodule RestaurantDashWeb.ItemDetailLive do
  @moduledoc """
  Customer-facing item detail page.
  Shows full item info, modifier selection with live price calculation,
  and an "Add to Cart" button (disabled — Phase 3 will wire this up).
  No authentication required.
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Menu, Tenancy}
  alias RestaurantDash.Menu.ModifierGroup
  alias RestaurantDash.Cart
  alias RestaurantDashWeb.CartHelpers

  @impl true
  def mount(%{"id" => id} = params, session, socket) do
    restaurant =
      case session["current_restaurant"] do
        %Tenancy.Restaurant{} = r -> r
        _ -> resolve_from_params(params)
      end

    case restaurant do
      nil ->
        socket =
          socket
          |> assign(:restaurant, nil)
          |> assign(:item, nil)
          |> assign(:not_found, true)
          |> assign(:selected_modifiers, %{})
          |> assign(:total_price, 0)
          |> CartHelpers.mount_cart(session)

        {:ok, socket}

      restaurant ->
        item = Menu.get_item_with_modifiers(restaurant.id, parse_id(id))

        case item do
          nil ->
            socket =
              socket
              |> assign(:restaurant, restaurant)
              |> assign(:item, nil)
              |> assign(:not_found, true)
              |> assign(:selected_modifiers, %{})
              |> assign(:total_price, 0)
              |> CartHelpers.mount_cart(session, restaurant.id)

            {:ok, socket}

          item ->
            socket =
              socket
              |> assign(:restaurant, restaurant)
              |> assign(:item, item)
              |> assign(:not_found, false)
              |> assign(:selected_modifiers, %{})
              |> assign(:total_price, item.price)
              |> CartHelpers.mount_cart(session, restaurant.id)

            {:ok, socket}
        end
    end
  end

  # ─── Events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_event(
        "select-modifier",
        %{"modifier-id" => mod_id_str, "group-id" => group_id_str},
        socket
      ) do
    mod_id = parse_id(mod_id_str)
    group_id = parse_id(group_id_str)
    item = socket.assigns.item
    selected = socket.assigns.selected_modifiers

    # Find the group to determine if it's single or multi-select
    group = Enum.find(item.modifier_groups, &(&1.id == group_id))

    new_selected =
      if group && ModifierGroup.multi_select?(group) do
        # Toggle this modifier in/out of set
        current = Map.get(selected, group_id, MapSet.new())

        if MapSet.member?(current, mod_id) do
          Map.put(selected, group_id, MapSet.delete(current, mod_id))
        else
          Map.put(selected, group_id, MapSet.put(current, mod_id))
        end
      else
        # Radio: set this as the only selection for the group
        current = Map.get(selected, group_id)

        if current == mod_id do
          # Deselect if clicking the same one
          Map.delete(selected, group_id)
        else
          Map.put(selected, group_id, mod_id)
        end
      end

    total = calculate_total(item, new_selected)

    {:noreply,
     socket
     |> assign(:selected_modifiers, new_selected)
     |> assign(:total_price, total)}
  end

  @impl true
  def handle_event("add-to-cart", _params, socket) do
    item = socket.assigns.item
    selected = socket.assigns.selected_modifiers
    total_price = socket.assigns.total_price

    modifier_adjustment = total_price - item.price

    # Build modifier_names list for display
    modifier_names =
      item.modifier_groups
      |> Enum.flat_map(fn group ->
        selection = Map.get(selected, group.id)
        selected_modifiers_for_group(group, selection)
      end)

    cart_item_attrs = %{
      menu_item_id: item.id,
      name: item.name,
      base_price: item.price,
      quantity: 1,
      selected_modifiers: selected,
      modifier_names: modifier_names,
      modifier_price_adjustment: modifier_adjustment
    }

    new_cart = Cart.add_item(socket.assigns.cart, cart_item_attrs)
    socket = CartHelpers.put_cart(socket, new_cart)

    {:noreply,
     socket
     |> put_flash(:info, "#{item.name} added to cart!")
     |> assign(:cart_drawer_open, true)}
  end

  @impl true
  def handle_event("toggle-cart", _params, socket) do
    {:noreply, assign(socket, :cart_drawer_open, !socket.assigns.cart_drawer_open)}
  end

  @impl true
  def handle_event("close-cart", _params, socket) do
    {:noreply, assign(socket, :cart_drawer_open, false)}
  end

  @impl true
  def handle_event("cart-update-quantity", %{"key" => key_str, "qty" => qty_str}, socket) do
    qty = String.to_integer(qty_str)
    key = deserialize_cart_key(key_str)
    new_cart = Cart.update_quantity(socket.assigns.cart, key, qty)
    {:noreply, CartHelpers.put_cart(socket, new_cart)}
  end

  @impl true
  def handle_event("cart-remove-item", %{"key" => key_str}, socket) do
    key = deserialize_cart_key(key_str)
    new_cart = Cart.remove_item(socket.assigns.cart, key)
    {:noreply, CartHelpers.put_cart(socket, new_cart)}
  end

  # ─── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50" id="item-detail-page">
      <%!-- Cart Drawer --%>
      <.cart_drawer
        cart={@cart}
        restaurant={@restaurant}
        open={@cart_drawer_open}
        primary_color={if @restaurant, do: @restaurant.primary_color, else: "#E63946"}
      />

      <%= if @not_found do %>
        <div class="flex items-center justify-center min-h-screen">
          <div class="text-center">
            <p class="text-2xl font-bold text-gray-800">Item not found</p>
            <p class="text-gray-500 mt-2">This item doesn't exist or is no longer available.</p>
            <a href="/menu" class="mt-4 inline-block text-blue-600 hover:underline">Back to menu</a>
          </div>
        </div>
      <% else %>
        <%!-- Header --%>
        <header class="text-white px-6 py-4" style={"background-color: #{@restaurant.primary_color}"}>
          <div class="max-w-2xl mx-auto flex items-center justify-between">
            <div class="flex items-center gap-4">
              <a
                href={"/menu?restaurant_slug=#{@restaurant.slug}"}
                class="text-white/80 hover:text-white text-sm"
              >
                ← Back to menu
              </a>
              <span class="text-white/50">|</span>
              <span class="font-medium text-sm">{@restaurant.name}</span>
            </div>
            <%!-- Cart Icon --%>
            <button
              phx-click="toggle-cart"
              class="relative flex items-center gap-2 bg-white/20 hover:bg-white/30 rounded-full px-4 py-2 text-sm font-medium transition-colors"
            >
              <span>🛒</span>
              <%= if Cart.item_count(@cart) > 0 do %>
                <span class="font-semibold">{Cart.item_count(@cart)}</span>
                <span class="text-white/80">
                  {format_price(Cart.calculate_totals(@cart).subtotal)}
                </span>
              <% else %>
                <span class="text-white/70">Cart</span>
              <% end %>
            </button>
          </div>
        </header>

        <main class="max-w-2xl mx-auto px-6 py-8">
          <div class="bg-white rounded-2xl border border-gray-200 overflow-hidden shadow-sm">
            <%!-- Image --%>
            <div class="w-full h-56 bg-gray-100 flex items-center justify-center overflow-hidden">
              <%= if @item.image_url do %>
                <img src={@item.image_url} alt={@item.name} class="w-full h-full object-cover" />
              <% else %>
                <span class="text-7xl">🍽️</span>
              <% end %>
            </div>

            <div class="p-6">
              <%!-- Item header --%>
              <div class="flex items-start justify-between gap-4">
                <div>
                  <div class="flex items-center gap-2">
                    <h1 class="text-2xl font-bold text-gray-900">{@item.name}</h1>
                    <%= unless @item.is_available do %>
                      <span class="text-sm font-medium px-3 py-1 rounded-full bg-gray-100 text-gray-500">
                        Sold Out
                      </span>
                    <% end %>
                  </div>
                  <%= if @item.description do %>
                    <p class="text-gray-600 mt-2 leading-relaxed">{@item.description}</p>
                  <% end %>
                </div>
                <div class="text-right flex-shrink-0">
                  <p class="text-2xl font-bold" style={"color: #{@restaurant.primary_color}"}>
                    {format_price(@total_price)}
                  </p>
                  <%= if @total_price != @item.price do %>
                    <p class="text-xs text-gray-400 mt-0.5">Base: {format_price(@item.price)}</p>
                  <% end %>
                </div>
              </div>

              <%!-- Modifier Groups --%>
              <%= if length(@item.modifier_groups) > 0 do %>
                <div class="mt-8 space-y-6">
                  <%= for group <- @item.modifier_groups do %>
                    <div>
                      <div class="flex items-center justify-between mb-3">
                        <h3 class="font-semibold text-gray-900">{group.name}</h3>
                        <span class="text-xs text-gray-400">
                          <%= cond do %>
                            <% ModifierGroup.optional?(group) and not ModifierGroup.multi_select?(group) -> %>
                              Optional
                            <% ModifierGroup.optional?(group) -> %>
                              Optional, select up to {group.max_selections || "unlimited"}
                            <% true -> %>
                              Required
                          <% end %>
                        </span>
                      </div>

                      <div class="space-y-2">
                        <%= for modifier <- group.modifiers do %>
                          <% is_multi = ModifierGroup.multi_select?(group) %>
                          <% is_selected =
                            modifier_selected?(@selected_modifiers, group.id, modifier.id, is_multi) %>
                          <label
                            class={"flex items-center justify-between gap-3 p-3 rounded-xl border cursor-pointer transition-colors #{if is_selected, do: "border-2 bg-opacity-5", else: "border-gray-200 hover:border-gray-300 bg-white"}"}
                            style={
                              if is_selected,
                                do:
                                  "border-color: #{@restaurant.primary_color}; background-color: #{@restaurant.primary_color}10;"
                            }
                          >
                            <div class="flex items-center gap-3">
                              <input
                                type={if is_multi, do: "checkbox", else: "radio"}
                                name={"group-#{group.id}"}
                                checked={is_selected}
                                phx-click="select-modifier"
                                phx-value-modifier-id={modifier.id}
                                phx-value-group-id={group.id}
                                data-modifier-type={if is_multi, do: "checkbox", else: "radio"}
                                class="text-blue-600"
                              />
                              <span class="text-sm font-medium text-gray-800">{modifier.name}</span>
                            </div>
                            <span class={"text-sm #{if modifier.price_adjustment > 0, do: "font-medium text-green-600", else: "text-gray-400"}"}>
                              {format_price_adjustment(modifier.price_adjustment)}
                            </span>
                          </label>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Add to Cart button --%>
              <div class="mt-8">
                <%= if @item.is_available do %>
                  <button
                    phx-click="add-to-cart"
                    class="w-full py-4 rounded-xl font-semibold text-white text-lg hover:opacity-90 active:scale-95 transition-all"
                    style={"background-color: #{@restaurant.primary_color}"}
                  >
                    Add to Cart — {format_price(@total_price)}
                  </button>
                <% else %>
                  <button
                    disabled
                    class="w-full py-4 rounded-xl font-semibold text-white text-lg opacity-40 cursor-not-allowed"
                    style={"background-color: #{@restaurant.primary_color}"}
                  >
                    Sold Out
                  </button>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Back link --%>
          <div class="text-center mt-6">
            <a
              href={"/menu?restaurant_slug=#{@restaurant.slug}"}
              class="text-sm text-gray-500 hover:text-gray-700"
            >
              ← Back to full menu
            </a>
          </div>
        </main>
      <% end %>
    </div>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────────

  # ─── Cart Drawer Component ────────────────────────────────────────────────────

  attr :cart, :any, required: true
  attr :restaurant, :any, default: nil
  attr :open, :boolean, default: false
  attr :primary_color, :string, default: "#E63946"

  defp cart_drawer(assigns) do
    ~H"""
    <%!-- Backdrop --%>
    <%= if @open do %>
      <div
        class="fixed inset-0 bg-black/40 z-40 transition-opacity"
        phx-click="close-cart"
      />
    <% end %>

    <%!-- Drawer --%>
    <div class={"fixed inset-y-0 right-0 z-50 w-full max-w-sm bg-white shadow-2xl transform transition-transform duration-300 #{if @open, do: "translate-x-0", else: "translate-x-full"}"}>
      <div class="flex flex-col h-full">
        <%!-- Header --%>
        <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-bold text-gray-900">Your Cart</h2>
          <button phx-click="close-cart" class="text-gray-400 hover:text-gray-600 text-2xl">
            ×
          </button>
        </div>

        <%!-- Items --%>
        <div class="flex-1 overflow-y-auto px-6 py-4">
          <%= if Cart.empty?(@cart) do %>
            <div class="flex flex-col items-center justify-center h-full text-center py-12">
              <span class="text-5xl mb-4">🛒</span>
              <p class="text-gray-500 font-medium">Your cart is empty</p>
              <p class="text-sm text-gray-400 mt-1">Add some items to get started</p>
              <%= if @restaurant do %>
                <a
                  href={"/menu?restaurant_slug=#{@restaurant.slug}"}
                  class="mt-4 text-sm font-medium hover:underline"
                  style={"color: #{@primary_color}"}
                  phx-click="close-cart"
                >
                  Browse menu →
                </a>
              <% end %>
            </div>
          <% else %>
            <div class="space-y-4">
              <%= for item <- @cart.items do %>
                <% key = serialize_cart_key(Cart.item_key(item)) %>
                <div class="flex items-start gap-3 py-3 border-b border-gray-100 last:border-0">
                  <div class="flex-1 min-w-0">
                    <p class="font-medium text-gray-900 text-sm truncate">{item.name}</p>
                    <%= if length(item.modifier_names) > 0 do %>
                      <p class="text-xs text-gray-500 mt-0.5">
                        {Enum.map_join(item.modifier_names, ", ", fn
                          {name, _} -> name
                          name -> name
                        end)}
                      </p>
                    <% end %>
                    <p class="text-sm font-semibold mt-1" style={"color: #{@primary_color}"}>
                      {format_price(item.line_total)}
                    </p>
                  </div>
                  <%!-- Quantity controls --%>
                  <div class="flex items-center gap-2 flex-shrink-0">
                    <button
                      phx-click="cart-update-quantity"
                      phx-value-key={key}
                      phx-value-qty={item.quantity - 1}
                      class="w-7 h-7 rounded-full border border-gray-300 flex items-center justify-center text-gray-600 hover:bg-gray-50 text-sm font-bold"
                    >
                      −
                    </button>
                    <span class="w-5 text-center text-sm font-medium">{item.quantity}</span>
                    <button
                      phx-click="cart-update-quantity"
                      phx-value-key={key}
                      phx-value-qty={item.quantity + 1}
                      class="w-7 h-7 rounded-full border border-gray-300 flex items-center justify-center text-gray-600 hover:bg-gray-50 text-sm font-bold"
                    >
                      +
                    </button>
                    <button
                      phx-click="cart-remove-item"
                      phx-value-key={key}
                      class="ml-1 text-red-400 hover:text-red-600 text-sm"
                      title="Remove"
                    >
                      🗑
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Footer / Totals --%>
        <%= unless Cart.empty?(@cart) do %>
          <% totals = Cart.calculate_totals(@cart) %>
          <div class="border-t border-gray-200 px-6 py-4 space-y-2">
            <div class="flex justify-between text-sm text-gray-600">
              <span>Subtotal</span>
              <span>{format_price(totals.subtotal)}</span>
            </div>
            <div class="flex justify-between text-sm text-gray-600">
              <span>Tax</span>
              <span>{format_price(totals.tax)}</span>
            </div>
            <div class="flex justify-between text-sm text-gray-600">
              <span>Delivery fee</span>
              <span>{format_price(totals.delivery_fee)}</span>
            </div>
            <div class="flex justify-between font-bold text-gray-900 pt-2 border-t border-gray-200">
              <span>Total</span>
              <span>{format_price(totals.total)}</span>
            </div>

            <a
              href="/checkout"
              class="block w-full text-center py-3 rounded-xl font-semibold text-white mt-3 hover:opacity-90 transition-opacity"
              style={"background-color: #{@primary_color}"}
            >
              Proceed to Checkout
            </a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ─── Private helpers ──────────────────────────────────────────────────────────

  defp selected_modifiers_for_group(_group, nil), do: []

  defp selected_modifiers_for_group(group, %MapSet{} = ids) do
    group.modifiers
    |> Enum.filter(&MapSet.member?(ids, &1.id))
    |> Enum.map(&{&1.name, &1.price_adjustment})
  end

  defp selected_modifiers_for_group(group, id) when is_integer(id) do
    case Enum.find(group.modifiers, &(&1.id == id)) do
      nil -> []
      mod -> [{mod.name, mod.price_adjustment}]
    end
  end

  defp serialize_cart_key({id, mod_ids}) do
    "#{inspect(id)}:#{Enum.join(mod_ids, ",")}"
  end

  defp deserialize_cart_key(str) do
    case String.split(str, ":", parts: 2) do
      [id_str, mods_str] ->
        id =
          case Integer.parse(id_str) do
            {n, ""} -> n
            _ -> id_str |> String.trim("\"")
          end

        mod_ids =
          case mods_str do
            "" ->
              []

            s ->
              s
              |> String.split(",")
              |> Enum.map(&String.to_integer/1)
          end

        {id, mod_ids}

      _ ->
        {str, []}
    end
  end

  defp resolve_from_params(%{"restaurant_slug" => slug}) when is_binary(slug) do
    Tenancy.get_restaurant_by_slug(slug)
  end

  defp resolve_from_params(_), do: nil

  defp parse_id(str) when is_binary(str) do
    case Integer.parse(str) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp parse_id(int) when is_integer(int), do: int
  defp parse_id(_), do: nil

  defp calculate_total(item, selected_modifiers) do
    adjustment =
      Enum.reduce(item.modifier_groups, 0, fn group, acc ->
        group_selection = Map.get(selected_modifiers, group.id)
        modifier_adjustment = calculate_group_adjustment(group, group_selection)
        acc + modifier_adjustment
      end)

    item.price + adjustment
  end

  defp calculate_group_adjustment(_group, nil), do: 0

  defp calculate_group_adjustment(group, %MapSet{} = selected_ids) do
    group.modifiers
    |> Enum.filter(&MapSet.member?(selected_ids, &1.id))
    |> Enum.sum_by(& &1.price_adjustment)
  end

  defp calculate_group_adjustment(group, selected_id) when is_integer(selected_id) do
    case Enum.find(group.modifiers, &(&1.id == selected_id)) do
      nil -> 0
      mod -> mod.price_adjustment
    end
  end

  defp modifier_selected?(selected, group_id, modifier_id, true = _multi) do
    case Map.get(selected, group_id) do
      %MapSet{} = set -> MapSet.member?(set, modifier_id)
      _ -> false
    end
  end

  defp modifier_selected?(selected, group_id, modifier_id, false = _multi) do
    Map.get(selected, group_id) == modifier_id
  end

  defp format_price(nil), do: "$0.00"

  defp format_price(price_cents) when is_integer(price_cents) do
    dollars = div(price_cents, 100)
    cents = rem(price_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end

  defp format_price_adjustment(0), do: "Included"
  defp format_price_adjustment(cents) when cents > 0, do: "+#{format_price(cents)}"
  defp format_price_adjustment(cents) when cents < 0, do: "-#{format_price(abs(cents))}"
end
