defmodule RestaurantDashWeb.PageController do
  use RestaurantDashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
