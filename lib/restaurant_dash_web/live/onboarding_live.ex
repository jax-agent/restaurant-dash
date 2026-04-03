defmodule RestaurantDashWeb.OnboardingLive do
  @moduledoc """
  Restaurant + owner account signup flow.
  Creates a restaurant and owner user in a single transaction.
  """
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Accounts, Repo, Tenancy}
  alias RestaurantDash.Tenancy.Restaurant
  alias RestaurantDash.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    changeset =
      %{
        restaurant: Tenancy.change_restaurant(%Restaurant{}),
        user: Accounts.change_user_registration(%User{})
      }

    {:ok,
     socket
     |> assign(:page_title, "Launch Your Restaurant")
     |> assign(:restaurant_form, to_form(changeset.restaurant, as: :restaurant))
     |> assign(:user_form, to_form(changeset.user, as: :user))
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("validate_restaurant", %{"restaurant" => params}, socket) do
    form =
      %Restaurant{}
      |> Tenancy.change_restaurant(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :restaurant)

    {:noreply, assign(socket, :restaurant_form, form)}
  end

  @impl true
  def handle_event("validate_user", %{"user" => params}, socket) do
    form =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :user)

    {:noreply, assign(socket, :user_form, form)}
  end

  @impl true
  def handle_event("signup", params, socket) do
    restaurant_params = Map.get(params, "restaurant", %{})
    user_params = Map.get(params, "user", %{})

    # Auto-generate slug from restaurant name
    slug = Tenancy.slugify(Map.get(restaurant_params, "name", ""))
    restaurant_params = Map.put(restaurant_params, "slug", slug)

    Repo.transaction(fn ->
      with {:ok, restaurant} <- Tenancy.create_restaurant(restaurant_params),
           {:ok, user} <-
             Accounts.register_user_with_role(%{
               email: Map.get(user_params, "email"),
               password: Map.get(user_params, "password"),
               name: Map.get(user_params, "name"),
               role: "owner",
               restaurant_id: restaurant.id
             }) do
        {restaurant, user}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, {_restaurant, user}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome! Your restaurant is ready. Please log in.")
         |> redirect(to: ~p"/users/log-in?email=#{user.email}")}

      {:error, %Ecto.Changeset{data: %Restaurant{}} = changeset} ->
        form = changeset |> Map.put(:action, :insert) |> to_form(as: :restaurant)

        {:noreply,
         socket
         |> assign(:restaurant_form, form)
         |> assign(:error_message, "Please fix the restaurant details below.")}

      {:error, %Ecto.Changeset{data: %User{}} = changeset} ->
        form = changeset |> Map.put(:action, :insert) |> to_form(as: :user)

        {:noreply,
         socket
         |> assign(:user_form, form)
         |> assign(:error_message, "Please fix the account details below.")}

      {:error, _} ->
        {:noreply, assign(socket, :error_message, "Something went wrong. Please try again.")}
    end
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-red-50 to-orange-50 flex items-center justify-center p-4">
      <div class="w-full max-w-lg">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Launch Your Restaurant</h1>
          <p class="text-gray-600 mt-2">Set up your delivery platform in minutes</p>
        </div>

        <div class="bg-white rounded-2xl shadow-lg p-8">
          <%= if @error_message do %>
            <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
              {@error_message}
            </div>
          <% end %>

          <form phx-submit="signup" id="signup-form">
            <%!-- Restaurant Details --%>
            <h2 class="text-lg font-semibold text-gray-800 mb-4">Restaurant Details</h2>

            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Restaurant Name *
              </label>
              <input
                type="text"
                name="restaurant[name]"
                value={@restaurant_form[:name].value}
                placeholder="El Coquí Kitchen"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400"
                required
              />
              <%= for error <- @restaurant_form[:name].errors do %>
                <p class="text-red-500 text-xs mt-1">{translate_error(error)}</p>
              <% end %>
            </div>

            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">Phone</label>
              <input
                type="tel"
                name="restaurant[phone]"
                value={@restaurant_form[:phone].value}
                placeholder="(415) 555-0100"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400"
              />
            </div>

            <%!-- Owner Account Details --%>
            <h2 class="text-lg font-semibold text-gray-800 mb-4 mt-6">Your Account</h2>

            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">Your Name *</label>
              <input
                type="text"
                name="user[name]"
                value={@user_form[:name].value}
                placeholder="Jane Smith"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400"
                required
              />
              <%= for error <- @user_form[:name].errors do %>
                <p class="text-red-500 text-xs mt-1">{translate_error(error)}</p>
              <% end %>
            </div>

            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">Email *</label>
              <input
                type="email"
                name="user[email]"
                value={@user_form[:email].value}
                placeholder="you@restaurant.com"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400"
                required
              />
              <%= for error <- @user_form[:email].errors do %>
                <p class="text-red-500 text-xs mt-1">{translate_error(error)}</p>
              <% end %>
            </div>

            <div class="mb-6">
              <label class="block text-sm font-medium text-gray-700 mb-1">Password *</label>
              <input
                type="password"
                name="user[password]"
                placeholder="At least 12 characters"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-400"
                required
              />
              <%= for error <- @user_form[:password].errors do %>
                <p class="text-red-500 text-xs mt-1">{translate_error(error)}</p>
              <% end %>
            </div>

            <button
              type="submit"
              class="w-full bg-red-500 hover:bg-red-600 text-white font-semibold py-3 px-6 rounded-lg transition-colors"
            >
              Launch My Restaurant →
            </button>
          </form>

          <p class="text-center text-sm text-gray-500 mt-4">
            Already have an account?
            <a href="/users/log-in" class="text-red-500 hover:underline">Log in</a>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
