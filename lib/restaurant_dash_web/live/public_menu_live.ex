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
      <div class="min-h-screen flex items-center justify-center" style="background: #0A0A0A;">
        <div class="text-center px-4 animate-fade-up">
          <div class="text-6xl mb-6">🔍</div>
          <h1 class="text-2xl font-bold text-white mb-2">Restaurant not found</h1>
          <p class="text-gray-500 mb-6">
            The restaurant you're looking for doesn't exist or has moved.
          </p>
          <a
            href="/"
            class="btn-primary inline-flex"
          >
            ← Back home
          </a>
        </div>
      </div>
    <% else %>
      <div
        class="min-h-screen"
        style="background: #0A0A0A; font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;"
      >
        <%!-- ═══ RESTAURANT HERO HEADER ═══ --%>
        <header
          class="relative text-white overflow-hidden"
          style={"background: linear-gradient(135deg, #{darken(@restaurant.primary_color)}, #{@restaurant.primary_color})"}
        >
          <%!-- Subtle pattern overlay --%>
          <div class="absolute inset-0 menu-hero-dots"></div>

          <div class="relative z-10 px-4 sm:px-6 py-10 sm:py-14 text-center max-w-3xl mx-auto">
            <%!-- Restaurant name --%>
            <h1 class="text-3xl sm:text-5xl font-extrabold tracking-tight mb-3 text-white drop-shadow-sm">
              {@restaurant.name}
            </h1>

            <%!-- Status + Rating row --%>
            <div class="flex items-center justify-center gap-3 flex-wrap mb-3">
              <%= case @open_status do %>
                <% {:open} -> %>
                  <span class="inline-flex items-center gap-1.5 bg-green-500 text-white text-xs font-bold px-3 py-1 rounded-full shadow-lg badge-open-pulse">
                    <span class="w-1.5 h-1.5 bg-[#111] rounded-full"></span> Open Now
                  </span>
                <% {:closed, reason} -> %>
                  <span class="inline-flex items-center gap-1.5 bg-black/30 text-white text-xs font-bold px-3 py-1 rounded-full">
                    <span class="w-1.5 h-1.5 bg-[#111]/60 rounded-full"></span> Closed — {reason}
                  </span>
              <% end %>

              <%= if @avg_rating do %>
                <a
                  href={"/reviews?restaurant_slug=#{@restaurant.slug}"}
                  class="inline-flex items-center gap-1 text-yellow-300 hover:text-yellow-100 font-semibold text-sm transition-colors"
                >
                  ★ {Float.round(@avg_rating, 1)}
                  <span class="text-white/60 font-normal">({@review_count})</span>
                </a>
              <% end %>
            </div>

            <%= if @restaurant.description do %>
              <p class="text-white/80 text-sm sm:text-base mt-2 max-w-md mx-auto leading-relaxed">
                {@restaurant.description}
              </p>
            <% end %>
            <%= if @restaurant.address do %>
              <p class="text-white/60 text-xs mt-2">
                📍 {@restaurant.address}, {@restaurant.city}, {@restaurant.state}
              </p>
            <% end %>
          </div>

          <%!-- Cart button top-right --%>
          <%= unless Cart.empty?(@cart) do %>
            <a
              href="/checkout"
              class="absolute top-4 right-4 sm:right-6 flex items-center gap-2 bg-[#111]/20 hover:bg-[#111]/30 backdrop-blur-sm rounded-full px-4 py-2 text-sm font-semibold transition-all border border-white/30 shadow-lg"
            >
              <span>🛒</span>
              <span class="font-bold">{Cart.item_count(@cart)}</span>
              <span class="text-white/80">{format_price(Cart.calculate_totals(@cart).subtotal)}</span>
            </a>
          <% end %>
        </header>

        <%!-- ═══ STICKY CATEGORY NAV ═══ --%>
        <%= if length(@menu) > 1 do %>
          <nav
            class="sticky top-0 z-20 bg-[#111]/95 backdrop-blur-md border-b border-[#222] shadow-sm"
            aria-label="Menu categories"
          >
            <div class="menu-category-nav">
              <%= for {cat, _items} <- @menu do %>
                <a
                  href={"#cat-#{cat.id}"}
                  class="menu-category-pill"
                >
                  {category_emoji(cat.name)} {cat.name}
                </a>
              <% end %>
            </div>
          </nav>
        <% end %>

        <%!-- ═══ MENU CONTENT ═══ --%>
        <main class="max-w-3xl mx-auto px-4 sm:px-6 py-8 sm:py-10 space-y-14">
          <%= if Enum.empty?(@menu) do %>
            <div class="empty-state">
              <span class="empty-state-icon">🍽</span>
              <h2 class="empty-state-title">Menu coming soon</h2>
              <p class="empty-state-text">No items available yet — check back soon!</p>
            </div>
          <% else %>
            <%= for {category, items} <- @menu do %>
              <section id={"cat-#{category.id}"} class="scroll-mt-20">
                <%!-- Category header --%>
                <div class="flex items-center gap-3 mb-6">
                  <span class="text-3xl">{category_emoji(category.name)}</span>
                  <div>
                    <h2 class="text-2xl font-extrabold text-white tracking-tight">
                      {category.name}
                    </h2>
                    <%= if category.description do %>
                      <p class="text-gray-500 text-sm mt-0.5">{category.description}</p>
                    <% end %>
                  </div>
                </div>

                <%= if Enum.empty?(items) do %>
                  <p class="text-gray-500 text-sm py-4">No items in this category yet.</p>
                <% else %>
                  <div class="space-y-3">
                    <%= for item <- items do %>
                      <a
                        href={"/menu/#{item.id}?restaurant_slug=#{@restaurant.slug}"}
                        class={"menu-item-card #{unless item.is_available, do: "opacity-60"}"}
                        id={"item-#{item.id}"}
                      >
                        <%!-- Emoji/image area --%>
                        <%= if item.image_url do %>
                          <div class="menu-item-image">
                            <img
                              src={item.image_url}
                              alt={item.name}
                              class="w-full h-full object-cover"
                            />
                          </div>
                        <% else %>
                          <div class="menu-item-emoji hidden sm:flex">
                            {item_emoji(item.name)}
                          </div>
                        <% end %>

                        <%!-- Item info --%>
                        <div class="flex-1 min-w-0 py-0.5">
                          <div class="flex items-start justify-between gap-3">
                            <div class="flex-1 min-w-0">
                              <div class="flex items-center gap-2 flex-wrap mb-1">
                                <h3 class="font-bold text-white text-base leading-tight">
                                  {item.name}
                                </h3>
                                <%= unless item.is_available do %>
                                  <span class="text-xs font-semibold px-2 py-0.5 rounded-full bg-gray-100 text-gray-500">
                                    Sold out
                                  </span>
                                <% end %>
                              </div>

                              <%= if item.description do %>
                                <p class="text-gray-500 text-sm leading-relaxed line-clamp-2">
                                  {item.description}
                                </p>
                              <% end %>

                              <%= if length(item.modifier_groups) > 0 do %>
                                <p class="text-xs text-gray-500 mt-1.5">
                                  {Enum.map_join(item.modifier_groups, " · ", & &1.name)}
                                </p>
                              <% end %>
                            </div>

                            <%!-- Price + add button --%>
                            <div class="flex flex-col items-end gap-2 flex-shrink-0">
                              <p
                                class="font-extrabold text-base tracking-tight"
                                style={"color: #{@restaurant.primary_color}"}
                              >
                                {format_price(item.price)}
                              </p>
                              <%= if item.is_available do %>
                                <span
                                  class="w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-lg shadow-md transition-transform hover:scale-110 active:scale-95"
                                  style={"background: #{@restaurant.primary_color}"}
                                >
                                  +
                                </span>
                              <% end %>
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

        <%!-- ═══ FOOTER ═══ --%>
        <footer class="text-center py-8 text-xs text-gray-500 border-t border-[#222] mt-8">
          <p>
            Powered by{" "}
            <a href="/" class="font-semibold text-gray-500 hover:text-white transition-colors">
              Order Base
            </a>
          </p>
        </footer>

        <%!-- ═══ STICKY CART BAR ═══ --%>
        <%= unless Cart.empty?(@cart) do %>
          <% totals = Cart.calculate_totals(@cart) %>
          <div class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 animate-fade-up">
            <a
              href="/checkout"
              class="flex items-center gap-4 text-white font-semibold px-8 py-3.5 rounded-xl bg-[#E63946] hover:bg-[#D32F3F] transition-all"
            >
              <span class="text-lg">🛒</span>
              <span>
                {Cart.item_count(@cart)} item{if Cart.item_count(@cart) != 1, do: "s"}
              </span>
              <span class="opacity-50">·</span>
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

  # Returns an emoji for the category based on name keywords
  defp category_emoji(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, ["drink", "beverage", "juice", "soda", "coffee", "tea", "agua"]) ->
        "🥤"

      String.contains?(name_lower, ["dessert", "postre", "sweet", "cake", "ice cream", "helado"]) ->
        "🍮"

      String.contains?(name_lower, ["appetizer", "starter", "snack", "entrada"]) ->
        "🫕"

      String.contains?(name_lower, ["pizza"]) ->
        "🍕"

      String.contains?(name_lower, ["burger", "sandwich", "sub"]) ->
        "🍔"

      String.contains?(name_lower, ["chicken", "pollo"]) ->
        "🍗"

      String.contains?(name_lower, ["seafood", "fish", "mariscos", "pescado"]) ->
        "🦞"

      String.contains?(name_lower, ["salad", "ensalada"]) ->
        "🥗"

      String.contains?(name_lower, ["soup", "sopa"]) ->
        "🥣"

      String.contains?(name_lower, ["breakfast", "desayuno", "brunch"]) ->
        "🍳"

      true ->
        "🥘"
    end
  end

  # Returns an emoji hint based on item name keywords
  defp item_emoji(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, ["pizza"]) -> "🍕"
      String.contains?(name_lower, ["burger", "hamburger"]) -> "🍔"
      String.contains?(name_lower, ["taco"]) -> "🌮"
      String.contains?(name_lower, ["rice", "arroz"]) -> "🍚"
      String.contains?(name_lower, ["chicken", "pollo"]) -> "🍗"
      String.contains?(name_lower, ["fish", "pescado", "salmon"]) -> "🐟"
      String.contains?(name_lower, ["steak", "carne", "beef"]) -> "🥩"
      String.contains?(name_lower, ["pasta", "spaghetti"]) -> "🍝"
      String.contains?(name_lower, ["salad", "ensalada"]) -> "🥗"
      String.contains?(name_lower, ["soup", "sopa"]) -> "🥣"
      String.contains?(name_lower, ["sandwich", "sub"]) -> "🥪"
      String.contains?(name_lower, ["cake", "pastel"]) -> "🎂"
      String.contains?(name_lower, ["ice cream", "helado"]) -> "🍦"
      String.contains?(name_lower, ["coffee", "cafe"]) -> "☕"
      String.contains?(name_lower, ["juice", "jugo"]) -> "🥤"
      String.contains?(name_lower, ["beer", "cerveza"]) -> "🍺"
      String.contains?(name_lower, ["wine", "vino"]) -> "🍷"
      true -> "🍽"
    end
  end

  # Darkens a hex color slightly for gradient effect
  defp darken(color) do
    color
  end
end
