defmodule RestaurantDashWeb.Router do
  use RestaurantDashWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RestaurantDashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RestaurantDashWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/orders/new", OrderFormLive, :new
    live "/orders/:id/edit", OrderFormLive, :edit
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
end
