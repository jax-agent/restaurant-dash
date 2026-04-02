defmodule RestaurantDashWeb.DriverSignupLive do
  @moduledoc """
  Driver registration flow.
  Creates a user with role "driver" + driver_profile.
  Driver must be approved by owner before receiving deliveries.
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.Drivers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:form, to_form(initial_form_data(), as: :driver))
      |> assign(:page_title, "Driver Sign Up")
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"driver" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :driver))}
  end

  @impl true
  def handle_event("submit", %{"driver" => params}, socket) do
    case Drivers.register_driver(params) do
      {:ok, %{user: _user, profile: _profile}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Registration successful! Your account is pending approval by the restaurant owner."
         )
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :driver))
         |> assign(:error, humanize_errors(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
          Driver Sign Up
        </h2>
        <p class="mt-2 text-center text-sm text-gray-600">
          Join as a delivery driver. Your account will be reviewed before activation.
        </p>
      </div>

      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          <.form for={@form} phx-submit="submit" phx-change="validate" class="space-y-6">
            <div>
              <label class="block text-sm font-medium text-gray-700">Full Name</label>
              <input
                type="text"
                name="driver[name]"
                value={@form[:name].value}
                required
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="Jane Smith"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Email Address</label>
              <input
                type="email"
                name="driver[email]"
                value={@form[:email].value}
                required
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="jane@example.com"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Password</label>
              <input
                type="password"
                name="driver[password]"
                required
                minlength="12"
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="Minimum 12 characters"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Phone Number</label>
              <input
                type="tel"
                name="driver[phone]"
                value={@form[:phone].value}
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="555-0100"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Vehicle Type</label>
              <select
                name="driver[vehicle_type]"
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
              >
                <option value="car">🚗 Car</option>
                <option value="bike">🚲 Bike</option>
                <option value="scooter">🛵 Scooter</option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">License Plate</label>
              <input
                type="text"
                name="driver[license_plate]"
                value={@form[:license_plate].value}
                class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="ABC-1234"
              />
            </div>

            <%= if @error do %>
              <div class="rounded-md bg-red-50 p-4">
                <p class="text-sm text-red-800">{@error}</p>
              </div>
            <% end %>

            <div>
              <button
                type="submit"
                class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                Create Driver Account
              </button>
            </div>
          </.form>

          <div class="mt-6 text-center">
            <p class="text-sm text-gray-600">
              Already have an account?
              <a href="/users/log-in" class="font-medium text-indigo-600 hover:text-indigo-500">
                Sign in
              </a>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp initial_form_data do
    %{
      "name" => "",
      "email" => "",
      "password" => "",
      "phone" => "",
      "vehicle_type" => "car",
      "license_plate" => ""
    }
  end

  defp humanize_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp humanize_errors(msg) when is_binary(msg), do: msg
end
