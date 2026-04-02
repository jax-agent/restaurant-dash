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

  @impl true
  def mount(%{"id" => id} = params, session, socket) do
    restaurant =
      case session["current_restaurant"] do
        %Tenancy.Restaurant{} = r -> r
        _ -> resolve_from_params(params)
      end

    case restaurant do
      nil ->
        {:ok,
         socket
         |> assign(:restaurant, nil)
         |> assign(:item, nil)
         |> assign(:not_found, true)
         |> assign(:selected_modifiers, %{})
         |> assign(:total_price, 0)}

      restaurant ->
        item = Menu.get_item_with_modifiers(restaurant.id, parse_id(id))

        case item do
          nil ->
            {:ok,
             socket
             |> assign(:restaurant, restaurant)
             |> assign(:item, nil)
             |> assign(:not_found, true)
             |> assign(:selected_modifiers, %{})
             |> assign(:total_price, 0)}

          item ->
            {:ok,
             socket
             |> assign(:restaurant, restaurant)
             |> assign(:item, item)
             |> assign(:not_found, false)
             |> assign(:selected_modifiers, %{})
             |> assign(:total_price, item.price)}
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

  # ─── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
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
          <div class="max-w-2xl mx-auto flex items-center gap-4">
            <a
              href={"/menu?restaurant_slug=#{@restaurant.slug}"}
              class="text-white/80 hover:text-white text-sm"
            >
              ← Back to menu
            </a>
            <span class="text-white/50">|</span>
            <span class="font-medium text-sm">{@restaurant.name}</span>
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
                <button
                  disabled
                  class="w-full py-4 rounded-xl font-semibold text-white text-lg opacity-60 cursor-not-allowed"
                  style={"background-color: #{@restaurant.primary_color}"}
                  title="Coming soon — ordering will be available in the next update"
                >
                  Add to Cart — {format_price(@total_price)}
                </button>
                <p class="text-center text-xs text-gray-400 mt-2">
                  Online ordering coming soon
                </p>
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
