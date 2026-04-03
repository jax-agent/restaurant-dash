defmodule RestaurantDashWeb.PublicMenuLive do
  @moduledoc """
  Customer-facing public menu display.
  No authentication required.

  The restaurant is resolved via:
  1. The ResolveRestaurant plug (subdomain-based in production)
  2. ?restaurant_slug= query param fallback (dev/test)
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Cart, Menu, Tenancy, Hours, Orders}
  alias RestaurantDashWeb.CartHelpers

  @impl true
  def mount(params, session, socket) do
    # Get restaurant from plug assign (set in session) or from query param
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
          |> assign(:menu, [])
          |> assign(:not_found, true)
          |> assign(:open_status, {:closed, "Unknown"})
          |> assign(:avg_rating, nil)
          |> assign(:review_count, 0)
          |> CartHelpers.mount_cart(session)

        {:ok, socket}

      restaurant ->
        menu = Menu.get_full_menu(restaurant.id)
        open_status = Hours.is_open?(restaurant.id, restaurant.timezone)
        {avg_rating, review_count} = Orders.get_restaurant_rating(restaurant.id)

        socket =
          socket
          |> assign(:restaurant, restaurant)
          |> assign(:menu, menu)
          |> assign(:not_found, false)
          |> assign(:open_status, open_status)
          |> assign(:avg_rating, avg_rating)
          |> assign(:review_count, review_count)
          |> CartHelpers.mount_cart(session, restaurant.id)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Support re-resolution if query param changes
    if socket.assigns.not_found do
      case resolve_from_params(params) do
        nil ->
          {:noreply, socket}

        restaurant ->
          menu = Menu.get_full_menu(restaurant.id)
          open_status = Hours.is_open?(restaurant.id, restaurant.timezone)
          {avg_rating, review_count} = Orders.get_restaurant_rating(restaurant.id)

          {:noreply,
           assign(socket,
             restaurant: restaurant,
             menu: menu,
             not_found: false,
             open_status: open_status,
             avg_rating: avg_rating,
             review_count: review_count
           )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @not_found do %>
      <div class="min-h-screen bg-gray-50 flex items-center justify-center">
        <div class="text-center">
          <p class="text-2xl font-bold text-gray-800">Restaurant not found</p>
          <p class="text-gray-500 mt-2">The restaurant you're looking for doesn't exist.</p>
          <a href="/" class="mt-4 inline-block text-blue-600 hover:underline">Go home</a>
        </div>
      </div>
    <% else %>
      <div class="min-h-screen bg-gray-50">
        <%!-- Header / Hero --%>
        <header
          class="text-white py-10 px-6 text-center relative"
          style={"background-color: #{@restaurant.primary_color}"}
        >
          <h1 class="text-3xl font-bold">{@restaurant.name}</h1>
          <div class="flex items-center justify-center gap-3 mt-2">
            <%!-- Open/Closed badge --%>
            <%= case @open_status do %>
              <% {:open} -> %>
                <span class="bg-green-500/90 text-white text-xs px-2 py-0.5 rounded-full font-medium">
                  ● Open Now
                </span>
              <% {:closed, reason} -> %>
                <span class="bg-red-500/80 text-white text-xs px-2 py-0.5 rounded-full font-medium">
                  Closed — {reason}
                </span>
            <% end %>
            <%!-- Average Rating --%>
            <%= if @avg_rating do %>
              <a
                href={"/reviews?restaurant_slug=#{@restaurant.slug}"}
                class="text-yellow-300 text-sm hover:text-yellow-100"
              >
                ★ {Float.round(@avg_rating, 1)} ({@review_count})
              </a>
            <% end %>
          </div>
          <%= if @restaurant.description do %>
            <p class="mt-2 text-white/80 text-sm max-w-lg mx-auto">{@restaurant.description}</p>
          <% end %>
          <%= if @restaurant.address do %>
            <p class="mt-1 text-white/70 text-xs">
              {@restaurant.address}, {@restaurant.city}, {@restaurant.state}
            </p>
          <% end %>

          <%!-- Cart Button (top-right) --%>
          <%= unless Cart.empty?(@cart) do %>
            <a
              href="/checkout"
              class="absolute top-4 right-6 flex items-center gap-2 bg-white/20 hover:bg-white/30 rounded-full px-4 py-2 text-sm font-medium transition-colors"
            >
              <span>🛒</span>
              <span class="font-semibold">{Cart.item_count(@cart)}</span>
              <span class="text-white/80">
                {format_price(Cart.calculate_totals(@cart).subtotal)}
              </span>
            </a>
          <% end %>
        </header>

        <%!-- Sticky category nav --%>
        <%= if length(@menu) > 1 do %>
          <nav class="sticky top-0 z-10 bg-white border-b border-gray-200 shadow-sm overflow-x-auto">
            <div class="flex gap-1 px-6 py-2 max-w-4xl mx-auto">
              <%= for {cat, _items} <- @menu do %>
                <a
                  href={"#cat-#{cat.id}"}
                  class="text-sm font-medium px-4 py-2 rounded-full whitespace-nowrap hover:bg-gray-100 transition-colors"
                >
                  {cat.name}
                </a>
              <% end %>
            </div>
          </nav>
        <% end %>

        <%!-- Menu sections --%>
        <main class="max-w-4xl mx-auto px-6 py-8 space-y-12">
          <%= if Enum.empty?(@menu) do %>
            <div class="text-center py-16">
              <p class="text-gray-400 text-lg">No menu items available yet.</p>
            </div>
          <% else %>
            <%= for {category, items} <- @menu do %>
              <section id={"cat-#{category.id}"} class="scroll-mt-20">
                <div class="mb-6">
                  <h2 class="text-2xl font-bold text-gray-900">{category.name}</h2>
                  <%= if category.description do %>
                    <p class="text-gray-500 text-sm mt-1">{category.description}</p>
                  <% end %>
                </div>

                <%= if Enum.empty?(items) do %>
                  <p class="text-gray-400 text-sm">No items in this category.</p>
                <% else %>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <%= for item <- items do %>
                      <a
                        href={"/menu/#{item.id}?restaurant_slug=#{@restaurant.slug}"}
                        class={"block bg-white rounded-xl border border-gray-200 overflow-hidden flex gap-4 p-4 hover:shadow-md transition-shadow #{unless item.is_available, do: "opacity-70"}"}
                        id={"item-#{item.id}"}
                      >
                        <%!-- Image --%>
                        <div class="w-20 h-20 rounded-lg bg-gray-100 flex-shrink-0 overflow-hidden flex items-center justify-center">
                          <%= if item.image_url do %>
                            <img
                              src={item.image_url}
                              alt={item.name}
                              class="w-full h-full object-cover"
                            />
                          <% else %>
                            <span class="text-3xl">🍽️</span>
                          <% end %>
                        </div>

                        <%!-- Info --%>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-start justify-between gap-2">
                            <div class="flex-1">
                              <div class="flex items-center gap-2 flex-wrap">
                                <h3 class="font-semibold text-gray-900 text-sm">{item.name}</h3>
                                <%= unless item.is_available do %>
                                  <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-gray-200 text-gray-600">
                                    Sold Out
                                  </span>
                                <% end %>
                              </div>
                              <%= if item.description do %>
                                <p class="text-xs text-gray-500 mt-1 leading-relaxed line-clamp-2">
                                  {item.description}
                                </p>
                              <% end %>

                              <%!-- Modifiers preview --%>
                              <%= if length(item.modifier_groups) > 0 do %>
                                <p class="text-xs text-gray-400 mt-1">
                                  {Enum.map_join(item.modifier_groups, ", ", & &1.name)}
                                </p>
                              <% end %>
                            </div>

                            <div class="text-right flex-shrink-0">
                              <p
                                class="font-bold text-sm"
                                style={"color: #{@restaurant.primary_color}"}
                              >
                                {format_price(item.price)}
                              </p>
                            </div>
                          </div>
                        </div>
                      </a>
                    <% end %>
                  </div>
                <% end %>
              </section>
            <% end %>
          <% end %>
        </main>

        <%!-- Footer --%>
        <footer class="text-center py-8 text-xs text-gray-400 border-t border-gray-200 mt-8">
          <p>
            Powered by <span class="font-medium">OrderBase</span>
          </p>
        </footer>

        <%!-- Sticky Cart Bar (shows when cart has items) --%>
        <%= unless Cart.empty?(@cart) do %>
          <% totals = Cart.calculate_totals(@cart) %>
          <div class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50">
            <a
              href="/checkout"
              class="flex items-center gap-4 text-white font-semibold px-8 py-4 rounded-full shadow-2xl hover:opacity-90 transition-all"
              style={"background-color: #{@restaurant.primary_color}"}
            >
              <span>🛒 {Cart.item_count(@cart)} item{if Cart.item_count(@cart) != 1, do: "s"}</span>
              <span class="opacity-60">·</span>
              <span>View Cart — {format_price(totals.total)}</span>
            </a>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────────

  defp resolve_from_params(%{"restaurant_slug" => slug}) when is_binary(slug) do
    Tenancy.get_restaurant_by_slug(slug)
  end

  defp resolve_from_params(_), do: nil

  defp format_price(price_cents) when is_integer(price_cents) do
    dollars = div(price_cents, 100)
    cents = rem(price_cents, 100)
    "$#{dollars}.#{String.pad_leading(Integer.to_string(cents), 2, "0")}"
  end

  defp format_price(_), do: "$0.00"
end
