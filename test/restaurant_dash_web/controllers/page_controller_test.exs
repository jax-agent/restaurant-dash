defmodule RestaurantDashWeb.PageControllerTest do
  use RestaurantDashWeb.ConnCase

  test "GET / redirects to or renders dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    # The route now renders a LiveView, so it returns 200
    assert conn.status == 200
  end
end
