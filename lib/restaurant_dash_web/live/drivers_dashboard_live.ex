defmodule RestaurantDashWeb.DriversDashboardLive do
  @moduledoc """
  Owner dashboard for managing drivers.
  Shows all drivers, their status, and allows approve/suspend.
  Real-time updates via PubSub.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  alias RestaurantDash.{Drivers, Tenancy}

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    case authorize(current_user) do
      {:ok, restaurant} ->
        if connected?(socket) do
          Drivers.subscribe_drivers(restaurant.id)
        end

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:restaurant, restaurant)
          |> assign(:page_title, "Driver Management")
          |> assign(:drivers, Drivers.list_profiles())

        {:ok, socket}

      {:error, :unauthenticated} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Owner or staff access required.")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    profile = Drivers.get_profile!(String.to_integer(id))

    case Drivers.approve_driver(profile) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Driver approved.")
         |> assign(:drivers, Drivers.list_profiles())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve driver.")}
    end
  end

  @impl true
  def handle_event("suspend", %{"id" => id}, socket) do
    profile = Drivers.get_profile!(String.to_integer(id))

    case Drivers.suspend_driver(profile) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Driver suspended.")
         |> assign(:drivers, Drivers.list_profiles())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to suspend driver.")}
    end
  end

  @impl true
  def handle_info({:driver_updated, _profile}, socket) do
    {:noreply, assign(socket, :drivers, Drivers.list_profiles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Driver Management</h1>
        <div class="flex gap-2">
          <span class="text-sm text-gray-500">
            {length(@drivers)} driver(s) registered
          </span>
        </div>
      </div>
      
    <!-- Stats bar -->
      <div class="grid grid-cols-4 gap-4 mb-8">
        <div class="bg-white rounded-lg p-4 shadow-sm border">
          <div class="text-2xl font-bold text-gray-900">{length(@drivers)}</div>
          <div class="text-sm text-gray-500">Total Drivers</div>
        </div>
        <div class="bg-white rounded-lg p-4 shadow-sm border">
          <div class="text-2xl font-bold text-green-600">
            {Enum.count(@drivers, & &1.is_approved)}
          </div>
          <div class="text-sm text-gray-500">Approved</div>
        </div>
        <div class="bg-white rounded-lg p-4 shadow-sm border">
          <div class="text-2xl font-bold text-blue-600">
            {Enum.count(@drivers, &(&1.status == "available"))}
          </div>
          <div class="text-sm text-gray-500">Available Now</div>
        </div>
        <div class="bg-white rounded-lg p-4 shadow-sm border">
          <div class="text-2xl font-bold text-orange-600">
            {Enum.count(@drivers, &(&1.status == "on_delivery"))}
          </div>
          <div class="text-sm text-gray-500">On Delivery</div>
        </div>
      </div>
      
    <!-- Driver list -->
      <div class="bg-white shadow-sm rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Driver
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Vehicle
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Approval
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for driver <- @drivers do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="font-medium text-gray-900">
                    {driver.user.name || driver.user.email}
                  </div>
                  <div class="text-sm text-gray-500">{driver.phone}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="text-sm text-gray-900">
                    {vehicle_icon(driver.vehicle_type)} {String.capitalize(driver.vehicle_type)}
                  </div>
                  <div class="text-xs text-gray-500">{driver.license_plate}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full #{status_color(driver.status)}"}>
                    {String.replace(driver.status, "_", " ") |> String.capitalize()}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <%= if driver.is_approved do %>
                    <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-800">
                      Approved
                    </span>
                  <% else %>
                    <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-yellow-100 text-yellow-800">
                      Pending
                    </span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                  <%= if driver.is_approved do %>
                    <button
                      phx-click="suspend"
                      phx-value-id={driver.id}
                      data-confirm="Suspend this driver?"
                      class="text-red-600 hover:text-red-900"
                    >
                      Suspend
                    </button>
                  <% else %>
                    <button
                      phx-click="approve"
                      phx-value-id={driver.id}
                      class="text-green-600 hover:text-green-900"
                    >
                      Approve
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>

            <%= if @drivers == [] do %>
              <tr>
                <td colspan="5" class="px-6 py-12 text-center text-gray-500">
                  No drivers registered yet.
                  Share the driver signup link to get started.
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <div class="mt-4 p-4 bg-gray-50 rounded-lg">
        <p class="text-sm text-gray-600">
          Driver signup link:
          <span class="font-mono text-indigo-600">{url(~p"/drivers/signup")}</span>
        </p>
      </div>
    </div>
    """
  end

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp authorize(nil), do: {:error, :unauthenticated}

  defp authorize(%{role: role, restaurant_id: restaurant_id})
       when role in ["owner", "staff"] do
    case Tenancy.get_restaurant(restaurant_id) do
      nil -> {:error, :unauthorized}
      restaurant -> {:ok, restaurant}
    end
  end

  defp authorize(_), do: {:error, :unauthorized}

  defp status_color("available"), do: "bg-green-100 text-green-800"
  defp status_color("on_delivery"), do: "bg-orange-100 text-orange-800"
  defp status_color("offline"), do: "bg-gray-100 text-gray-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp vehicle_icon("car"), do: "🚗"
  defp vehicle_icon("bike"), do: "🚲"
  defp vehicle_icon("scooter"), do: "🛵"
  defp vehicle_icon(_), do: "🚗"
end
