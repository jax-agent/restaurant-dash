defmodule RestaurantDashWeb.LocationsLive do
  @moduledoc "Owner dashboard for managing restaurant locations."
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.Locations

  @impl true
  def mount(_params, session, socket) do
    restaurant = session["current_restaurant"]

    if is_nil(restaurant) do
      {:ok, push_navigate(socket, to: "/")}
    else
      {:ok,
       socket
       |> assign(:restaurant, restaurant)
       |> assign(:locations, Locations.list_locations(restaurant.id))
       |> assign(:show_form, false)
       |> assign(:editing, nil)
       |> assign(:form_data, default_form())
       |> assign(:form_errors, %{})}
    end
  end

  @impl true
  def handle_event("show-form", _, socket) do
    {:noreply,
     assign(socket, show_form: true, editing: nil, form_data: default_form(), form_errors: %{})}
  end

  @impl true
  def handle_event("hide-form", _, socket) do
    {:noreply, assign(socket, show_form: false)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    loc = Locations.get_location!(String.to_integer(id))

    form_data = %{
      "name" => loc.name,
      "address" => loc.address,
      "city" => loc.city || "",
      "state" => loc.state || "",
      "zip" => loc.zip || "",
      "phone" => loc.phone || "",
      "lat" => if(loc.lat, do: to_string(loc.lat), else: ""),
      "lng" => if(loc.lng, do: to_string(loc.lng), else: "")
    }

    {:noreply,
     assign(socket, show_form: true, editing: loc, form_data: form_data, form_errors: %{})}
  end

  @impl true
  def handle_event("update-field", %{"field" => field, "value" => value}, socket) do
    {:noreply, assign(socket, form_data: Map.put(socket.assigns.form_data, field, value))}
  end

  @impl true
  def handle_event("save", _, socket) do
    restaurant = socket.assigns.restaurant
    form = socket.assigns.form_data

    attrs =
      %{
        restaurant_id: restaurant.id,
        name: form["name"],
        address: form["address"],
        city: form["city"],
        state: form["state"],
        zip: form["zip"],
        phone: form["phone"],
        lat: parse_float(form["lat"]),
        lng: parse_float(form["lng"])
      }
      |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
      |> Map.new()
      |> Map.put(:restaurant_id, restaurant.id)

    result =
      if socket.assigns.editing do
        Locations.update_location(socket.assigns.editing, attrs)
      else
        Locations.create_location(attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:locations, Locations.list_locations(restaurant.id))
         |> assign(:show_form, false)
         |> assign(:form_errors, %{})}

      {:error, cs} ->
        {:noreply, assign(socket, form_errors: errors_from_changeset(cs))}
    end
  end

  @impl true
  def handle_event("set-primary", %{"id" => id}, socket) do
    loc = Locations.get_location!(String.to_integer(id))
    {:ok, _} = Locations.set_primary(loc)

    {:noreply, assign(socket, locations: Locations.list_locations(socket.assigns.restaurant.id))}
  end

  @impl true
  def handle_event("deactivate", %{"id" => id}, socket) do
    loc = Locations.get_location!(String.to_integer(id))
    {:ok, _} = Locations.deactivate_location(loc)

    {:noreply, assign(socket, locations: Locations.list_locations(socket.assigns.restaurant.id))}
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp default_form do
    %{
      "name" => "",
      "address" => "",
      "city" => "",
      "state" => "",
      "zip" => "",
      "phone" => "",
      "lat" => "",
      "lng" => ""
    }
  end

  defp parse_float(""), do: nil
  defp parse_float(nil), do: nil

  defp parse_float(str) do
    case Float.parse(str) do
      {v, _} -> v
      :error -> nil
    end
  end

  defp errors_from_changeset(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map(fn {k, v} -> {to_string(k), Enum.join(v, ", ")} end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Locations</h1>
        <button
          phx-click="show-form"
          class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 font-medium"
        >
          + Add Location
        </button>
      </div>

      <%= if @show_form do %>
        <div class="bg-white border border-gray-200 rounded-xl p-6 mb-6 shadow-sm">
          <h2 class="text-lg font-semibold mb-4">
            {if @editing, do: "Edit Location", else: "Add Location"}
          </h2>
          <div class="grid grid-cols-2 gap-4">
            <%= for {field, label, placeholder} <- [
              {"name", "Location Name", "Downtown"},
              {"address", "Street Address", "123 Main St"},
              {"city", "City", "Chicago"},
              {"state", "State", "IL"},
              {"zip", "ZIP Code", "60601"},
              {"phone", "Phone", "(312) 555-0100"},
              {"lat", "Latitude (optional)", "41.8781"},
              {"lng", "Longitude (optional)", "-87.6298"}
            ] do %>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">{label}</label>
                <input
                  type="text"
                  value={@form_data[field]}
                  phx-blur="update-field"
                  phx-value-field={field}
                  placeholder={placeholder}
                  class="w-full border border-gray-300 rounded-lg px-3 py-2"
                />
                <%= if @form_errors[field] do %>
                  <p class="text-red-500 text-xs mt-1">{@form_errors[field]}</p>
                <% end %>
              </div>
            <% end %>
          </div>
          <div class="flex gap-3 mt-4">
            <button
              phx-click="save"
              class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 font-medium"
            >
              Save
            </button>
            <button
              phx-click="hide-form"
              class="border border-gray-300 text-gray-700 px-4 py-2 rounded-lg"
            >
              Cancel
            </button>
          </div>
        </div>
      <% end %>

      <%= if Enum.empty?(@locations) do %>
        <div class="bg-white border border-gray-200 rounded-xl p-12 text-center text-gray-500">
          <p class="text-lg">No locations yet</p>
          <p class="text-sm">Add your first location to enable multi-location ordering</p>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for loc <- @locations do %>
            <div class={"bg-white border rounded-xl p-4 flex items-start justify-between #{if loc.is_primary, do: "border-indigo-300", else: "border-gray-200"}"}>
              <div>
                <div class="flex items-center gap-2">
                  <h3 class="font-semibold text-gray-900">{loc.name}</h3>
                  <%= if loc.is_primary do %>
                    <span class="bg-indigo-100 text-indigo-700 text-xs px-2 py-0.5 rounded-full font-medium">
                      Primary
                    </span>
                  <% end %>
                  <%= if !loc.is_active do %>
                    <span class="bg-gray-100 text-gray-600 text-xs px-2 py-0.5 rounded-full">
                      Inactive
                    </span>
                  <% end %>
                </div>
                <p class="text-gray-600 text-sm mt-1">
                  {loc.address}{if loc.city, do: ", #{loc.city}"}{if loc.state, do: ", #{loc.state}"}{if loc.zip,
                    do: " #{loc.zip}"}
                </p>
                <%= if loc.phone do %>
                  <p class="text-gray-500 text-sm">{loc.phone}</p>
                <% end %>
              </div>
              <div class="flex gap-2">
                <button
                  phx-click="edit"
                  phx-value-id={loc.id}
                  class="text-indigo-600 hover:text-indigo-800 text-sm"
                >
                  Edit
                </button>
                <%= if !loc.is_primary and loc.is_active do %>
                  <button
                    phx-click="set-primary"
                    phx-value-id={loc.id}
                    class="text-gray-600 hover:text-gray-800 text-sm"
                  >
                    Set Primary
                  </button>
                <% end %>
                <%= if loc.is_active do %>
                  <button
                    phx-click="deactivate"
                    phx-value-id={loc.id}
                    data-confirm="Deactivate this location?"
                    class="text-red-500 hover:text-red-700 text-sm"
                  >
                    Deactivate
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
