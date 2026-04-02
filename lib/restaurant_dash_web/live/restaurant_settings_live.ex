defmodule RestaurantDashWeb.RestaurantSettingsLive do
  @moduledoc """
  Restaurant settings LiveView. Allows owners to edit their restaurant profile.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Tenancy, Payments, Delivery}
  alias RestaurantDash.Integrations.Clover, as: CloverIntegration
  alias RestaurantDash.Delivery.DeliveryZone

  @impl true
  def mount(params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        # Re-load restaurant from DB in case stripe_account_id was just saved
        restaurant = Tenancy.get_restaurant!(restaurant.id)

        # Handle Stripe return from onboarding
        stripe_just_connected =
          params["stripe_mock"] == "true" or params["stripe_connected"] == "true"

        # If coming back from Stripe with an account_id in params (mock mode)
        restaurant =
          if params["account_id"] && is_nil(restaurant.stripe_account_id) do
            case Payments.save_stripe_account_id(restaurant, params["account_id"]) do
              {:ok, updated} -> updated
              _ -> restaurant
            end
          else
            restaurant
          end

        form = restaurant |> Tenancy.change_restaurant() |> to_form(as: :restaurant)

        zones = Delivery.list_zones(restaurant.id)

        # Handle Clover return
        clover_just_connected = params["clover_connected"] == "true"

        {:ok,
         socket
         |> assign(:current_user, current_user)
         |> assign(:restaurant, restaurant)
         |> assign(:form, form)
         |> assign(:saved, false)
         |> assign(:stripe_connecting, false)
         |> assign(:stripe_just_connected, stripe_just_connected)
         |> assign(:clover_just_connected, clover_just_connected)
         |> assign(:clover_connecting, false)
         |> assign(:clover_merchant_name, nil)
         |> assign(:zones, zones)
         |> assign(:zone_form, nil)
         |> assign(:editing_zone, nil)}

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
  def handle_event("connect-stripe", _params, socket) do
    restaurant = socket.assigns.restaurant
    base_url = RestaurantDashWeb.Endpoint.url()
    return_url = base_url <> "/dashboard/settings?stripe_connected=true"
    refresh_url = base_url <> "/dashboard/settings"

    socket = assign(socket, :stripe_connecting, true)

    case Payments.begin_stripe_onboarding(restaurant, return_url, refresh_url) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:stripe_connecting, false)
         |> put_flash(:error, "Stripe connection failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("connect-clover", _params, socket) do
    base_url = RestaurantDashWeb.Endpoint.url()
    redirect_uri = base_url <> "/dashboard/settings/clover/callback"

    socket = assign(socket, :clover_connecting, true)
    url = CloverIntegration.authorization_url(redirect_uri)
    {:noreply, redirect(socket, external: url)}
  end

  @impl true
  def handle_event("disconnect-clover", _params, socket) do
    case CloverIntegration.disconnect(socket.assigns.restaurant) do
      {:ok, restaurant} ->
        {:noreply,
         socket
         |> assign(:restaurant, restaurant)
         |> assign(:clover_just_connected, false)
         |> put_flash(:info, "Clover disconnected.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect Clover.")}
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
  def handle_event("new_zone", _params, socket) do
    zone = %DeliveryZone{}
    form = Delivery.change_zone(zone) |> to_form(as: :zone)
    {:noreply, socket |> assign(:editing_zone, zone) |> assign(:zone_form, form)}
  end

  def handle_event("edit_zone", %{"id" => id}, socket) do
    zone = Delivery.get_zone!(String.to_integer(id))
    form = Delivery.change_zone(zone) |> to_form(as: :zone)
    {:noreply, socket |> assign(:editing_zone, zone) |> assign(:zone_form, form)}
  end

  def handle_event("cancel_zone", _params, socket) do
    {:noreply, socket |> assign(:editing_zone, nil) |> assign(:zone_form, nil)}
  end

  def handle_event("validate_zone", %{"zone" => params}, socket) do
    form =
      (socket.assigns.editing_zone || %DeliveryZone{})
      |> Delivery.change_zone(normalize_zone_params(params))
      |> Map.put(:action, :validate)
      |> to_form(as: :zone)

    {:noreply, assign(socket, :zone_form, form)}
  end

  def handle_event("save_zone", %{"zone" => params}, socket) do
    normalized = normalize_zone_params(params)

    result =
      case socket.assigns.editing_zone do
        %DeliveryZone{id: nil} ->
          Delivery.create_zone(Map.put(normalized, "restaurant_id", socket.assigns.restaurant.id))

        %DeliveryZone{} = zone ->
          Delivery.update_zone(zone, normalized)
      end

    case result do
      {:ok, _zone} ->
        zones = Delivery.list_zones(socket.assigns.restaurant.id)

        {:noreply,
         socket
         |> assign(:zones, zones)
         |> assign(:editing_zone, nil)
         |> assign(:zone_form, nil)
         |> put_flash(:info, "Delivery zone saved.")}

      {:error, changeset} ->
        form = changeset |> Map.put(:action, :update) |> to_form(as: :zone)
        {:noreply, assign(socket, :zone_form, form)}
    end
  end

  def handle_event("delete_zone", %{"id" => id}, socket) do
    zone = Delivery.get_zone!(String.to_integer(id))
    Delivery.delete_zone(zone)
    zones = Delivery.list_zones(socket.assigns.restaurant.id)
    {:noreply, socket |> assign(:zones, zones) |> put_flash(:info, "Zone deleted.")}
  end

  # Normalize zone params: parse delivery_fee, min_order from dollar strings to cents
  # Also parse polygon_json textarea into the polygon field
  defp normalize_zone_params(params) do
    params
    |> Map.update("delivery_fee", 0, fn v ->
      case Float.parse(to_string(v)) do
        {f, _} -> round(f * 100)
        :error -> 0
      end
    end)
    |> Map.update("min_order", 0, fn v ->
      case Float.parse(to_string(v)) do
        {f, _} -> round(f * 100)
        :error -> 0
      end
    end)
    |> parse_polygon_json()
  end

  defp parse_polygon_json(%{"polygon_json" => json} = params) when is_binary(json) do
    polygon =
      case Jason.decode(json) do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    params
    |> Map.delete("polygon_json")
    |> Map.put("polygon", polygon)
  end

  defp parse_polygon_json(params), do: params

  defp format_cents(nil), do: "0.00"
  defp format_cents(0), do: "0.00"

  defp format_cents(cents) when is_integer(cents),
    do: :erlang.float_to_binary(cents / 100, decimals: 2)

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

        <%!-- Delivery Fee Settings --%>
        <div class="mt-8 bg-white rounded-xl border border-gray-200 p-6">
          <h2 class="text-base font-semibold text-gray-800 mb-1">Delivery Fee Settings</h2>
          <p class="text-sm text-gray-500 mb-4">
            Configure how delivery fees are calculated for customers.
          </p>
          <.form for={@form} phx-submit="save" phx-change="validate" id="fee-settings-form">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <.input
                  field={@form[:fee_mode]}
                  type="select"
                  label="Fee Mode"
                  options={[
                    {"Flat fee", "flat"},
                    {"Zone-based", "zone"},
                    {"Distance-based", "distance"}
                  ]}
                />
              </div>
              <div>
                <.input
                  field={@form[:base_delivery_fee]}
                  type="number"
                  label="Base Delivery Fee (cents)"
                  placeholder="299"
                />
              </div>
              <div>
                <.input
                  field={@form[:per_mile_rate]}
                  type="number"
                  label="Per Mile Rate (cents)"
                  placeholder="50"
                />
              </div>
              <div>
                <.input
                  field={@form[:free_delivery_threshold]}
                  type="number"
                  label="Free Delivery Threshold (cents, 0 = disabled)"
                  placeholder="0"
                />
              </div>
              <div>
                <.input
                  field={@form[:driver_base_pay]}
                  type="number"
                  label="Driver Base Pay (cents)"
                  placeholder="500"
                />
              </div>
              <div>
                <.input
                  field={@form[:driver_per_mile_pay]}
                  type="number"
                  label="Driver Per Mile Pay (cents)"
                  placeholder="50"
                />
              </div>
            </div>
            <button
              type="submit"
              class="mt-4 px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-semibold hover:bg-blue-700"
            >
              Save Fee Settings
            </button>
          </.form>
        </div>

        <%!-- Delivery Zones --%>
        <div class="mt-8 bg-white rounded-xl border border-gray-200 p-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h2 class="text-base font-semibold text-gray-800">Delivery Zones</h2>
              <p class="text-sm text-gray-500 mt-1">
                Define polygon-based delivery zones with custom fees.
              </p>
            </div>
            <button
              phx-click="new_zone"
              class="px-3 py-1.5 bg-blue-600 text-white text-sm font-semibold rounded-lg hover:bg-blue-700"
            >
              + Add Zone
            </button>
          </div>

          <%= if @zone_form do %>
            <div class="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-xl">
              <h3 class="font-semibold text-blue-900 mb-3">
                {if @editing_zone && @editing_zone.id, do: "Edit Zone", else: "New Zone"}
              </h3>
              <.form for={@zone_form} phx-submit="save_zone" phx-change="validate_zone">
                <div class="grid grid-cols-2 gap-3">
                  <div class="col-span-2">
                    <.input
                      field={@zone_form[:name]}
                      type="text"
                      label="Zone Name"
                      placeholder="Downtown"
                    />
                  </div>
                  <div>
                    <.input
                      field={@zone_form[:delivery_fee]}
                      type="number"
                      label="Delivery Fee ($)"
                      step="0.01"
                      placeholder="2.99"
                    />
                  </div>
                  <div>
                    <.input
                      field={@zone_form[:min_order]}
                      type="number"
                      label="Min Order ($)"
                      step="0.01"
                      placeholder="10.00"
                    />
                  </div>
                  <div class="col-span-2">
                    <label class="block text-sm font-medium text-gray-700 mb-1">
                      Polygon (JSON array of [lat, lng] points)
                    </label>
                    <textarea
                      name="zone[polygon_json]"
                      placeholder="[[37.785,-122.425],[37.785,-122.395],[37.765,-122.395],[37.765,-122.425]]"
                      class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm font-mono resize-y focus:ring-2 focus:ring-blue-400 focus:outline-none"
                      rows="3"
                    >{Jason.encode!(@editing_zone.polygon || [])}</textarea>
                    <p class="text-xs text-gray-500 mt-1">
                      Enter coordinates as JSON array, e.g. [[lat,lng],[lat,lng],...]
                    </p>
                  </div>
                </div>
                <div class="flex gap-3 mt-3">
                  <button
                    type="submit"
                    class="px-4 py-2 bg-blue-600 text-white text-sm font-semibold rounded-lg hover:bg-blue-700"
                  >
                    Save Zone
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_zone"
                    class="px-4 py-2 bg-gray-100 text-gray-700 text-sm font-semibold rounded-lg hover:bg-gray-200"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          <% end %>

          <%= if @zones == [] do %>
            <div class="text-center py-8 text-gray-400">
              <p>No delivery zones defined.</p>
              <p class="text-sm mt-1">Add zones to restrict delivery to specific areas.</p>
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for zone <- @zones do %>
                <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div>
                    <p class="font-medium text-sm text-gray-900">{zone.name}</p>
                    <p class="text-xs text-gray-500">
                      Fee: ${format_cents(zone.delivery_fee)} · Min: ${format_cents(zone.min_order)} · {length(
                        zone.polygon
                      )} points {unless zone.is_active, do: "· ⚫ Inactive"}
                    </p>
                  </div>
                  <div class="flex gap-2">
                    <button
                      phx-click="edit_zone"
                      phx-value-id={zone.id}
                      class="text-xs text-blue-600 hover:text-blue-800 font-medium"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="delete_zone"
                      phx-value-id={zone.id}
                      data-confirm="Delete this zone?"
                      class="text-xs text-red-600 hover:text-red-800 font-medium"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Stripe Connect Section --%>
        <div class="mt-8 bg-white rounded-xl border border-gray-200 p-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h2 class="text-base font-semibold text-gray-800">Payment Processing</h2>
              <p class="text-sm text-gray-500 mt-1">
                Connect Stripe to accept online payments from customers
              </p>
            </div>
            <%= if Payments.mock_mode?() do %>
              <span class="text-xs bg-yellow-100 text-yellow-700 px-2 py-1 rounded-full font-medium">
                Demo Mode
              </span>
            <% end %>
          </div>

          <%= if Payments.stripe_connected?(@restaurant) do %>
            <div class="flex items-center gap-3 p-4 bg-green-50 border border-green-200 rounded-lg">
              <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm">
                ✓
              </div>
              <div>
                <p class="text-sm font-medium text-green-800">Stripe Connected</p>
                <p class="text-xs text-green-600 font-mono mt-0.5">
                  {@restaurant.stripe_account_id}
                </p>
              </div>
            </div>
            <%= if @stripe_just_connected do %>
              <p class="text-sm text-green-600 mt-2">
                🎉 Your Stripe account has been connected successfully!
              </p>
            <% end %>
          <% else %>
            <div class="space-y-3">
              <%= if Payments.mock_mode?() do %>
                <div class="p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
                  <p class="text-xs text-yellow-700">
                    <strong>Demo Mode:</strong>
                    No real Stripe keys configured. Connect will simulate the flow with a fake account ID.
                    Set <code class="font-mono">STRIPE_SECRET_KEY</code>
                    to enable real payments.
                  </p>
                </div>
              <% end %>
              <button
                phx-click="connect-stripe"
                disabled={@stripe_connecting}
                class={"flex items-center gap-2 px-4 py-2.5 bg-indigo-600 hover:bg-indigo-700 text-white font-semibold rounded-lg transition-colors text-sm #{if @stripe_connecting, do: "opacity-60 cursor-not-allowed"}"}
              >
                <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M13.976 9.15c-2.172-.806-3.356-1.426-3.356-2.409 0-.831.683-1.305 1.901-1.305 2.227 0 4.515.858 6.09 1.631l.89-5.494C18.252.975 15.697 0 12.165 0 9.667 0 7.589.654 6.104 1.872 4.56 3.147 3.757 4.992 3.757 7.218c0 4.039 2.467 5.76 6.476 7.219 2.585.92 3.445 1.574 3.445 2.583 0 .98-.84 1.545-2.354 1.545-1.875 0-4.965-.921-6.99-2.109l-.9 5.555C5.175 22.99 8.385 24 11.714 24c2.641 0 4.843-.624 6.328-1.813 1.664-1.305 2.525-3.236 2.525-5.732 0-4.128-2.524-5.851-6.591-7.305z" />
                </svg>
                <%= if @stripe_connecting do %>
                  Connecting...
                <% else %>
                  Connect Stripe Account
                <% end %>
              </button>
            </div>
          <% end %>
        </div>
        <%!-- Clover POS Section --%>
        <div class="mt-8 bg-white rounded-xl border border-gray-200 p-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h2 class="text-base font-semibold text-gray-800">Clover POS Integration</h2>
              <p class="text-sm text-gray-500 mt-1">
                Connect your Clover POS to sync menus, push orders, and reconcile payments
              </p>
            </div>
            <%= if CloverIntegration.mock_mode?() do %>
              <span class="text-xs bg-yellow-100 text-yellow-700 px-2 py-1 rounded-full font-medium">
                Demo Mode
              </span>
            <% end %>
          </div>

          <%= if CloverIntegration.connected?(@restaurant) do %>
            <div class="flex items-center gap-3 p-4 bg-green-50 border border-green-200 rounded-lg">
              <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm">
                ✓
              </div>
              <div class="flex-1">
                <p class="text-sm font-medium text-green-800">Clover Connected</p>
                <p class="text-xs text-green-600 font-mono mt-0.5">
                  Merchant ID: {@restaurant.clover_merchant_id}
                </p>
                <%= if @restaurant.clover_connected_at do %>
                  <p class="text-xs text-green-500 mt-0.5">
                    Connected {@restaurant.clover_connected_at |> Calendar.strftime("%b %d, %Y")}
                  </p>
                <% end %>
              </div>
              <button
                phx-click="disconnect-clover"
                data-confirm="Disconnect Clover? This will remove your POS integration."
                class="px-3 py-1.5 bg-red-100 text-red-700 text-sm font-medium rounded-lg hover:bg-red-200"
              >
                Disconnect
              </button>
            </div>
            <%= if @clover_just_connected do %>
              <p class="text-sm text-green-600 mt-2">
                🎉 Clover connected successfully! You can now import your menu and push orders.
              </p>
            <% end %>
          <% else %>
            <div class="space-y-3">
              <%= if CloverIntegration.mock_mode?() do %>
                <div class="p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
                  <p class="text-xs text-yellow-700">
                    <strong>Demo Mode:</strong>
                    No Clover API keys configured. Connect will simulate the OAuth flow.
                    Set <code class="font-mono">CLOVER_APP_ID</code>
                    and <code class="font-mono">CLOVER_APP_SECRET</code>
                    to enable real Clover integration.
                  </p>
                </div>
              <% end %>
              <button
                phx-click="connect-clover"
                disabled={@clover_connecting}
                class={"flex items-center gap-2 px-4 py-2.5 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-lg transition-colors text-sm #{if @clover_connecting, do: "opacity-60 cursor-not-allowed"}"}
              >
                <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z" />
                </svg>
                <%= if @clover_connecting do %>
                  Connecting to Clover...
                <% else %>
                  Connect Clover POS
                <% end %>
              </button>
            </div>
          <% end %>
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
