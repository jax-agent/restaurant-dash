defmodule RestaurantDashWeb.RestaurantSettingsLive do
  @moduledoc """
  Restaurant settings LiveView. Allows owners to edit their restaurant profile.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.Tenancy

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        form = restaurant |> Tenancy.change_restaurant() |> to_form(as: :restaurant)

        {:ok,
         socket
         |> assign(:current_user, current_user)
         |> assign(:restaurant, restaurant)
         |> assign(:form, form)
         |> assign(:saved, false)}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to access settings.")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"restaurant" => params}, socket) do
    form =
      socket.assigns.restaurant
      |> Tenancy.change_restaurant(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :restaurant)

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"restaurant" => params}, socket) do
    case Tenancy.update_restaurant(socket.assigns.restaurant, params) do
      {:ok, restaurant} ->
        form = restaurant |> Tenancy.change_restaurant() |> to_form(as: :restaurant)

        {:noreply,
         socket
         |> assign(:restaurant, restaurant)
         |> assign(:form, form)
         |> assign(:saved, true)
         |> put_flash(:info, "Settings saved!")}

      {:error, changeset} ->
        form = changeset |> Map.put(:action, :update) |> to_form(as: :restaurant)
        {:noreply, socket |> assign(:form, form) |> assign(:saved, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <header class="bg-white border-b border-gray-200 px-6 py-4">
        <div class="max-w-4xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-3">
            <a href="/dashboard" class="text-gray-500 hover:text-gray-700">← Dashboard</a>
            <span class="text-gray-300">|</span>
            <h1 class="text-lg font-bold text-gray-900">Restaurant Settings</h1>
          </div>
          <p class="text-sm text-gray-500">{@restaurant.name}</p>
        </div>
      </header>

      <main class="max-w-4xl mx-auto px-6 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <%!-- Settings Form --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-base font-semibold text-gray-800 mb-4">Restaurant Details</h2>

            <.form for={@form} phx-submit="save" phx-change="validate" id="settings-form">
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Restaurant Name *
                  </label>
                  <.input field={@form[:name]} type="text" placeholder="My Restaurant" />
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
                  <.input
                    field={@form[:description]}
                    type="textarea"
                    placeholder="Tell customers about your restaurant"
                    rows="3"
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Phone</label>
                  <.input field={@form[:phone]} type="tel" placeholder="(415) 555-0100" />
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Address</label>
                  <.input field={@form[:address]} type="text" placeholder="123 Main St" />
                </div>

                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">City</label>
                    <.input field={@form[:city]} type="text" placeholder="San Francisco" />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">State</label>
                    <.input field={@form[:state]} type="text" placeholder="CA" />
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">ZIP Code</label>
                  <.input field={@form[:zip]} type="text" placeholder="94103" />
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Brand Color
                  </label>
                  <div class="flex items-center gap-3">
                    <.input field={@form[:primary_color]} type="color" />
                    <span class="text-sm text-gray-500">
                      {@form[:primary_color].value || "#E63946"}
                    </span>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Logo URL</label>
                  <.input
                    field={@form[:logo_url]}
                    type="url"
                    placeholder="https://example.com/logo.png"
                  />
                </div>
              </div>

              <div class="mt-6">
                <button
                  type="submit"
                  class="w-full text-white font-semibold py-2.5 px-4 rounded-lg transition-colors"
                  style={"background-color: #{@restaurant.primary_color}"}
                >
                  Save Settings
                </button>
              </div>
            </.form>
          </div>

          <%!-- Live Preview --%>
          <div>
            <h2 class="text-base font-semibold text-gray-800 mb-4">Live Preview</h2>

            <div
              class="rounded-xl overflow-hidden shadow-md"
              id="branding-preview"
            >
              <div
                class="p-4 text-white"
                style={"background-color: #{@form[:primary_color].value || @restaurant.primary_color}"}
              >
                <div class="flex items-center gap-2">
                  <%= if @form[:logo_url].value && @form[:logo_url].value != "" do %>
                    <img
                      src={@form[:logo_url].value}
                      class="w-8 h-8 rounded object-cover"
                      alt="logo"
                    />
                  <% else %>
                    <div class="w-8 h-8 rounded bg-white/20 flex items-center justify-center font-bold">
                      {String.first(@form[:name].value || @restaurant.name)}
                    </div>
                  <% end %>
                  <span class="font-bold">{@form[:name].value || @restaurant.name}</span>
                </div>
              </div>

              <div class="bg-white p-4">
                <p class="text-sm text-gray-600">
                  {@form[:description].value || @restaurant.description || "No description yet"}
                </p>
                <div class="mt-3 flex items-center gap-2 text-sm text-gray-500">
                  <span>📍</span>
                  <span>
                    {[
                      @form[:city].value || @restaurant.city,
                      @form[:state].value || @restaurant.state
                    ]
                    |> Enum.filter(&(&1 && &1 != ""))
                    |> Enum.join(", ")}
                  </span>
                </div>
              </div>
            </div>

            <%= if @saved do %>
              <div class="mt-4 p-3 bg-green-50 border border-green-200 rounded-lg text-green-700 text-sm">
                ✅ Settings saved successfully!
              </div>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # ─── Private ──────────────────────────────────────────────────────────────

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

  defp authorize(user) do
    if user.role in ~w(owner) do
      case user.restaurant_id && Tenancy.get_restaurant(user.restaurant_id) do
        nil -> {:error, :unauthorized}
        restaurant -> {:ok, restaurant}
      end
    else
      {:error, :unauthorized}
    end
  end
end
