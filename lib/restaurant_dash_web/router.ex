defmodule RestaurantDashWeb.Router do
  use RestaurantDashWeb, :router

  import RestaurantDashWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RestaurantDashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug RestaurantDashWeb.Plugs.ResolveRestaurant
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RestaurantDashWeb do
    pipe_through :browser

    live "/", LandingLive, :index
    live "/menu", PublicMenuLive, :index
    live "/menu/:id", ItemDetailLive, :show
    live "/signup", OnboardingLive, :new

    # Owner dashboard
    live "/dashboard", OwnerDashboardLive, :index
    live "/dashboard/orders", DashboardLive, :index
    live "/dashboard/menu", MenuManagementLive, :index
    live "/dashboard/settings", RestaurantSettingsLive, :edit

    live "/orders/new", OrderFormLive, :new
    live "/orders/:id/edit", OrderFormLive, :edit

    # Phase 3: Customer ordering
    live "/checkout", CheckoutLive, :index
    live "/orders/:id/track", TrackOrderLive, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:restaurant_dash, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RestaurantDashWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", RestaurantDashWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", RestaurantDashWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", RestaurantDashWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
