defmodule RestaurantDash.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RestaurantDashWeb.Telemetry,
      RestaurantDash.Repo,
      {DNSCluster, query: Application.get_env(:restaurant_dash, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RestaurantDash.PubSub},
      {Oban, Application.fetch_env!(:restaurant_dash, Oban)},
      # Start to serve requests, typically the last entry
      RestaurantDashWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RestaurantDash.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RestaurantDashWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
