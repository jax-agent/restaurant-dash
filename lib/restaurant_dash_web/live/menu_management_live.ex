defmodule RestaurantDashWeb.MenuManagementLive do
  @moduledoc """
  Owner-facing menu management page.
  Allows owners to create, edit, delete, and reorder categories and items.
  Requires owner role.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Menu, Tenancy}
  alias RestaurantDash.Menu.{Category, Item}

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        categories = Menu.list_categories(restaurant.id)
        selected_category = List.first(categories)

        items =
          if selected_category,
            do: Menu.list_items_by_category(restaurant.id, selected_category.id),
            else: []

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:restaurant, restaurant)
          |> assign(:categories, categories)
          |> assign(:selected_category, selected_category)
          |> assign(:items, items)
          |> assign(:show_category_form, false)
          |> assign(:editing_category, nil)
          |> assign(:show_item_form, false)
          |> assign(:editing_item, nil)
          |> assign(
            :category_changeset,
            Menu.change_category(%Category{}, %{restaurant_id: restaurant.id})
          )
          |> assign(:item_changeset, Menu.change_item(%Item{}, %{restaurant_id: restaurant.id}))

        {:ok, socket}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to access the menu.")
         |> redirect(to: ~p"/")}
    end
  end

  # ─── Category Events ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("show-add-category", _params, socket) do
    changeset =
      Menu.change_category(%Category{}, %{restaurant_id: socket.assigns.restaurant.id})

    {:noreply,
     socket
     |> assign(:show_category_form, true)
     |> assign(:editing_category, nil)
     |> assign(:category_changeset, changeset)}
  end

  @impl true
  def handle_event("edit-category", %{"id" => id}, socket) do
    cat = Menu.get_category(socket.assigns.restaurant.id, String.to_integer(id))
    changeset = Menu.change_category(cat, %{})

    {:noreply,
     socket
     |> assign(:show_category_form, true)
     |> assign(:editing_category, cat)
     |> assign(:category_changeset, changeset)}
  end

  @impl true
  def handle_event("save-category", %{"category" => params}, socket) do
    restaurant = socket.assigns.restaurant
    params = Map.put(params, "restaurant_id", restaurant.id)

    result =
      case socket.assigns.editing_category do
        nil -> Menu.create_category(params)
        cat -> Menu.update_category(cat, params)
      end

    case result do
      {:ok, saved_cat} ->
        categories = Menu.list_categories(restaurant.id)

        # Update selected_category if it was the one we just edited
        selected =
          case socket.assigns.selected_category do
            nil -> nil
            sel when sel.id == saved_cat.id -> saved_cat
            sel -> sel
          end

        {:noreply,
         socket
         |> assign(:categories, categories)
         |> assign(:selected_category, selected)
         |> assign(:show_category_form, false)
         |> assign(:editing_category, nil)
         |> put_flash(:info, "Category saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :category_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("cancel-category-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_category_form, false)
     |> assign(:editing_category, nil)}
  end

  @impl true
  def handle_event("delete-category", %{"id" => id}, socket) do
    restaurant = socket.assigns.restaurant
    cat = Menu.get_category(restaurant.id, String.to_integer(id))

    if cat do
      {:ok, _} = Menu.delete_category(cat)
    end

    categories = Menu.list_categories(restaurant.id)

    # If deleted category was selected, reset selection
    selected =
      cond do
        socket.assigns.selected_category &&
            socket.assigns.selected_category.id == String.to_integer(id) ->
          List.first(categories)

        true ->
          socket.assigns.selected_category
      end

    items = if selected, do: Menu.list_items_by_category(restaurant.id, selected.id), else: []

    {:noreply,
     socket
     |> assign(:categories, categories)
     |> assign(:selected_category, selected)
     |> assign(:items, items)}
  end

  @impl true
  def handle_event("select-category", %{"id" => id}, socket) do
    restaurant = socket.assigns.restaurant
    cat = Menu.get_category(restaurant.id, String.to_integer(id))
    items = if cat, do: Menu.list_items_by_category(restaurant.id, cat.id), else: []

    {:noreply,
     socket
     |> assign(:selected_category, cat)
     |> assign(:items, items)
     |> assign(:show_item_form, false)
     |> assign(:editing_item, nil)}
  end

  @impl true
  def handle_event("move-category-up", %{"id" => id}, socket) do
    restaurant = socket.assigns.restaurant
    categories = socket.assigns.categories
    idx = Enum.find_index(categories, &(&1.id == String.to_integer(id)))

    if idx && idx > 0 do
      reordered =
        categories
        |> List.delete_at(idx)
        |> List.insert_at(idx - 1, Enum.at(categories, idx))

      Menu.reorder_categories(restaurant.id, Enum.map(reordered, & &1.id))
      updated = Menu.list_categories(restaurant.id)
      {:noreply, assign(socket, :categories, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move-category-down", %{"id" => id}, socket) do
    restaurant = socket.assigns.restaurant
    categories = socket.assigns.categories
    idx = Enum.find_index(categories, &(&1.id == String.to_integer(id)))

    if idx && idx < length(categories) - 1 do
      reordered =
        categories
        |> List.delete_at(idx)
        |> List.insert_at(idx + 1, Enum.at(categories, idx))

      Menu.reorder_categories(restaurant.id, Enum.map(reordered, & &1.id))
      updated = Menu.list_categories(restaurant.id)
      {:noreply, assign(socket, :categories, updated)}
    else
      {:noreply, socket}
    end
  end

  # ─── Item Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("show-add-item", _params, socket) do
    changeset =
      Menu.change_item(%Item{}, %{restaurant_id: socket.assigns.restaurant.id})

    {:noreply,
     socket
     |> assign(:show_item_form, true)
     |> assign(:editing_item, nil)
     |> assign(:item_changeset, changeset)}
  end

  @impl true
  def handle_event("edit-item", %{"id" => id}, socket) do
    item = Menu.get_item(socket.assigns.restaurant.id, String.to_integer(id))
    changeset = Menu.change_item(item, %{})

    {:noreply,
     socket
     |> assign(:show_item_form, true)
     |> assign(:editing_item, item)
     |> assign(:item_changeset, changeset)}
  end

  @impl true
  def handle_event("save-item", %{"item" => params}, socket) do
    restaurant = socket.assigns.restaurant
    params = Map.put(params, "restaurant_id", restaurant.id)

    # Convert price from dollars string to cents integer
    params = convert_price(params)

    result =
      case socket.assigns.editing_item do
        nil -> Menu.create_item(params)
        item -> Menu.update_item(item, params)
      end

    case result do
      {:ok, _item} ->
        items =
          case socket.assigns.selected_category do
            nil -> []
            cat -> Menu.list_items_by_category(restaurant.id, cat.id)
          end

        {:noreply,
         socket
         |> assign(:items, items)
         |> assign(:show_item_form, false)
         |> assign(:editing_item, nil)
         |> put_flash(:info, "Item saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :item_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("cancel-item-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_item_form, false)
     |> assign(:editing_item, nil)}
  end

  @impl true
  def handle_event("delete-item", %{"id" => id}, socket) do
    restaurant = socket.assigns.restaurant
    item = Menu.get_item(restaurant.id, String.to_integer(id))

    if item do
      {:ok, _} = Menu.delete_item(item)
    end

    items =
      case socket.assigns.selected_category do
        nil -> []
        cat -> Menu.list_items_by_category(restaurant.id, cat.id)
      end

    {:noreply, assign(socket, :items, items)}
  end

  @impl true
  def handle_event("toggle-availability", %{"id" => id}, socket) do
    restaurant = socket.assigns.restaurant
    item = Menu.get_item(restaurant.id, String.to_integer(id))

    if item do
      {:ok, _} = Menu.toggle_item_availability(item)
    end

    items =
      case socket.assigns.selected_category do
        nil -> []
        cat -> Menu.list_items_by_category(restaurant.id, cat.id)
      end

    {:noreply, assign(socket, :items, items)}
  end

  # ─── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%!-- Header --%>
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-7xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div
              class="w-8 h-8 rounded-lg flex items-center justify-center text-white font-bold text-sm"
              style={"background-color: #{@restaurant.primary_color}"}
            >
              {String.first(@restaurant.name)}
            </div>
            <div>
              <h1 class="text-lg font-bold text-gray-900">{@restaurant.name}</h1>
              <p class="text-xs text-gray-500">Menu Management</p>
            </div>
          </div>

          <nav class="flex items-center gap-4 text-sm">
            <a href="/dashboard" class="text-gray-600 hover:text-gray-900 font-medium">Overview</a>
            <a href="/dashboard/orders" class="text-gray-600 hover:text-gray-900 font-medium">
              Orders
            </a>
            <a
              href="/dashboard/menu"
              class="font-semibold"
              style={"color: #{@restaurant.primary_color}"}
            >
              Menu
            </a>
            <a href="/dashboard/settings" class="text-gray-600 hover:text-gray-900 font-medium">
              Settings
            </a>
            <a
              href="/users/log-out"
              data-method="delete"
              class="text-red-500 hover:text-red-700 font-medium"
            >
              Log out
            </a>
          </nav>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-6 py-8">
        <div class="flex gap-6">
          <%!-- Left panel: Categories --%>
          <div class="w-72 flex-shrink-0">
            <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
              <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">
                <h2 class="font-semibold text-gray-800 text-sm">Categories</h2>
                <button
                  phx-click="show-add-category"
                  class="text-xs font-medium px-3 py-1.5 rounded-lg text-white"
                  style={"background-color: #{@restaurant.primary_color}"}
                >
                  Add Category
                </button>
              </div>

              <%!-- Category form --%>
              <%= if @show_category_form do %>
                <div class="px-4 py-3 bg-gray-50 border-b border-gray-100">
                  <.form
                    for={@category_changeset}
                    id="category-form"
                    phx-submit="save-category"
                  >
                    <div class="space-y-2">
                      <input
                        type="text"
                        name="category[name]"
                        value={Ecto.Changeset.get_field(@category_changeset, :name)}
                        placeholder="Category name"
                        class="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2"
                        style={"--tw-ring-color: #{@restaurant.primary_color}"}
                        required
                      />
                      <input
                        type="text"
                        name="category[description]"
                        value={Ecto.Changeset.get_field(@category_changeset, :description)}
                        placeholder="Description (optional)"
                        class="w-full text-sm border border-gray-300 rounded-lg px-3 py-2"
                      />
                      <div class="flex gap-2">
                        <button
                          type="submit"
                          class="flex-1 text-xs font-medium py-1.5 rounded-lg text-white"
                          style={"background-color: #{@restaurant.primary_color}"}
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel-category-form"
                          class="flex-1 text-xs font-medium py-1.5 rounded-lg bg-gray-200 text-gray-700"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              <% end %>

              <%!-- Category list --%>
              <ul class="divide-y divide-gray-100">
                <%= if Enum.empty?(@categories) do %>
                  <li class="px-4 py-6 text-center text-sm text-gray-400">
                    No categories yet
                  </li>
                <% else %>
                  <%= for {cat, idx} <- Enum.with_index(@categories) do %>
                    <li
                      class={"flex items-center gap-2 px-4 py-3 cursor-pointer hover:bg-gray-50 #{if @selected_category && @selected_category.id == cat.id, do: "bg-blue-50 border-l-2 border-blue-500", else: ""}"}
                      id={"cat-#{cat.id}"}
                    >
                      <div class="flex flex-col gap-1 mr-1">
                        <%= if idx > 0 do %>
                          <button
                            phx-click="move-category-up"
                            phx-value-id={cat.id}
                            data-action="move-category-up"
                            data-id={cat.id}
                            class="text-gray-400 hover:text-gray-600 leading-none"
                            title="Move up"
                          >
                            ▲
                          </button>
                        <% end %>
                        <%= if idx < length(@categories) - 1 do %>
                          <button
                            phx-click="move-category-down"
                            phx-value-id={cat.id}
                            data-action="move-category-down"
                            data-id={cat.id}
                            class="text-gray-400 hover:text-gray-600 leading-none"
                            title="Move down"
                          >
                            ▼
                          </button>
                        <% end %>
                      </div>

                      <button
                        phx-click="select-category"
                        phx-value-id={cat.id}
                        data-action="select-category"
                        data-id={cat.id}
                        class="flex-1 text-left text-sm font-medium text-gray-800 truncate"
                      >
                        {cat.name}
                        <%= unless cat.is_active do %>
                          <span class="ml-1 text-xs text-gray-400">(hidden)</span>
                        <% end %>
                      </button>

                      <div class="flex gap-1">
                        <button
                          phx-click="edit-category"
                          phx-value-id={cat.id}
                          data-action="edit-category"
                          data-id={cat.id}
                          class="text-gray-400 hover:text-blue-500 text-xs"
                          title="Edit"
                        >
                          ✏️
                        </button>
                        <button
                          phx-click="delete-category"
                          phx-value-id={cat.id}
                          data-action="delete-category"
                          data-id={cat.id}
                          class="text-gray-400 hover:text-red-500 text-xs"
                          title="Delete"
                          data-confirm="Delete this category?"
                        >
                          🗑️
                        </button>
                      </div>
                    </li>
                  <% end %>
                <% end %>
              </ul>
            </div>
          </div>

          <%!-- Right panel: Items --%>
          <div class="flex-1">
            <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
              <div class="flex items-center justify-between px-6 py-3 border-b border-gray-100">
                <h2 class="font-semibold text-gray-800 text-sm">
                  <%= if @selected_category do %>
                    {@selected_category.name} Items
                  <% else %>
                    Items — Select a category
                  <% end %>
                </h2>
                <%= if @selected_category do %>
                  <button
                    phx-click="show-add-item"
                    class="text-xs font-medium px-3 py-1.5 rounded-lg text-white"
                    style={"background-color: #{@restaurant.primary_color}"}
                  >
                    Add Item
                  </button>
                <% end %>
              </div>

              <%!-- Item form --%>
              <%= if @show_item_form do %>
                <div class="px-6 py-4 bg-gray-50 border-b border-gray-100">
                  <.form
                    for={@item_changeset}
                    id="item-form"
                    phx-submit="save-item"
                  >
                    <div class="grid grid-cols-2 gap-3">
                      <div class="col-span-2">
                        <label class="text-xs font-medium text-gray-600">Name *</label>
                        <input
                          type="text"
                          name="item[name]"
                          value={Ecto.Changeset.get_field(@item_changeset, :name)}
                          placeholder="Item name"
                          class="w-full mt-1 text-sm border border-gray-300 rounded-lg px-3 py-2"
                          required
                        />
                      </div>
                      <div class="col-span-2">
                        <label class="text-xs font-medium text-gray-600">Description</label>
                        <input
                          type="text"
                          name="item[description]"
                          value={Ecto.Changeset.get_field(@item_changeset, :description)}
                          placeholder="Description"
                          class="w-full mt-1 text-sm border border-gray-300 rounded-lg px-3 py-2"
                        />
                      </div>
                      <div>
                        <label class="text-xs font-medium text-gray-600">Price ($) *</label>
                        <input
                          type="text"
                          name="item[price]"
                          value={
                            format_price_for_input(Ecto.Changeset.get_field(@item_changeset, :price))
                          }
                          placeholder="0.00"
                          class="w-full mt-1 text-sm border border-gray-300 rounded-lg px-3 py-2"
                          required
                        />
                      </div>
                      <div>
                        <label class="text-xs font-medium text-gray-600">Image URL</label>
                        <input
                          type="text"
                          name="item[image_url]"
                          value={Ecto.Changeset.get_field(@item_changeset, :image_url)}
                          placeholder="https://..."
                          class="w-full mt-1 text-sm border border-gray-300 rounded-lg px-3 py-2"
                        />
                      </div>
                      <input
                        type="hidden"
                        name="item[menu_category_id]"
                        value={@selected_category && @selected_category.id}
                      />
                      <div class="col-span-2 flex gap-2">
                        <button
                          type="submit"
                          class="flex-1 text-sm font-medium py-2 rounded-lg text-white"
                          style={"background-color: #{@restaurant.primary_color}"}
                        >
                          Save Item
                        </button>
                        <button
                          type="button"
                          phx-click="cancel-item-form"
                          class="flex-1 text-sm font-medium py-2 rounded-lg bg-gray-200 text-gray-700"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              <% end %>

              <%!-- Items list --%>
              <%= if is_nil(@selected_category) do %>
                <div class="px-6 py-12 text-center text-gray-400">
                  <p>Select a category to see its items</p>
                </div>
              <% else %>
                <%= if Enum.empty?(@items) do %>
                  <div class="px-6 py-12 text-center text-gray-400">
                    <p>No items in this category yet</p>
                    <button
                      phx-click="show-add-item"
                      class="mt-3 text-sm font-medium px-4 py-2 rounded-lg text-white"
                      style={"background-color: #{@restaurant.primary_color}"}
                    >
                      Add First Item
                    </button>
                  </div>
                <% else %>
                  <div class="divide-y divide-gray-100">
                    <%= for item <- @items do %>
                      <div
                        class={"flex items-center gap-4 px-6 py-4 #{unless item.is_available, do: "opacity-60 bg-red-50"}"}
                        id={"item-#{item.id}"}
                      >
                        <%!-- Image placeholder or actual image --%>
                        <div class="w-14 h-14 rounded-lg bg-gray-100 flex items-center justify-center flex-shrink-0 overflow-hidden">
                          <%= if item.image_url do %>
                            <img
                              src={item.image_url}
                              alt={item.name}
                              class="w-full h-full object-cover"
                            />
                          <% else %>
                            <span class="text-2xl">🍽️</span>
                          <% end %>
                        </div>

                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2">
                            <p class="font-medium text-gray-900 text-sm truncate">{item.name}</p>
                            <%= unless item.is_available do %>
                              <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-red-100 text-red-700 eighty-sixed">
                                86&#39;d
                              </span>
                            <% end %>
                            <%= unless item.is_active do %>
                              <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-gray-100 text-gray-500">
                                Hidden
                              </span>
                            <% end %>
                          </div>
                          <%= if item.description do %>
                            <p class="text-xs text-gray-500 mt-0.5 truncate">{item.description}</p>
                          <% end %>
                          <p
                            class="text-sm font-semibold mt-1"
                            style={"color: #{@restaurant.primary_color}"}
                          >
                            {Item.format_price(item.price)}
                          </p>
                        </div>

                        <div class="flex items-center gap-2 flex-shrink-0">
                          <button
                            phx-click="toggle-availability"
                            phx-value-id={item.id}
                            data-action="toggle-availability"
                            data-id={item.id}
                            class={"text-xs font-medium px-3 py-1.5 rounded-lg #{if item.is_available, do: "bg-orange-100 text-orange-700 hover:bg-orange-200", else: "bg-green-100 text-green-700 hover:bg-green-200"}"}
                            title={
                              if item.is_available, do: "Mark as 86'd", else: "Mark as available"
                            }
                          >
                            {if item.is_available, do: "86", else: "Un-86"}
                          </button>
                          <button
                            phx-click="edit-item"
                            phx-value-id={item.id}
                            data-action="edit-item"
                            data-id={item.id}
                            class="text-gray-400 hover:text-blue-500 text-sm"
                            title="Edit"
                          >
                            ✏️
                          </button>
                          <button
                            phx-click="delete-item"
                            phx-value-id={item.id}
                            data-action="delete-item"
                            data-id={item.id}
                            class="text-gray-400 hover:text-red-500 text-sm"
                            title="Delete"
                            data-confirm="Delete this item?"
                          >
                            🗑️
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────────

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

  defp convert_price(%{"price" => price} = params) when is_binary(price) do
    case Float.parse(price) do
      {dollars, _} -> Map.put(params, "price", round(dollars * 100))
      :error -> params
    end
  end

  defp convert_price(params), do: params

  defp format_price_for_input(nil), do: ""
  defp format_price_for_input(0), do: "0.00"

  defp format_price_for_input(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    c = rem(cents, 100)
    "#{dollars}.#{String.pad_leading(Integer.to_string(c), 2, "0")}"
  end
end
