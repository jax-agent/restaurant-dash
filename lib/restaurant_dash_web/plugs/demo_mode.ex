defmodule RestaurantDashWeb.Plugs.DemoMode do
  @moduledoc """
  Reads the `:demo_mode` key from the session and assigns it on the conn.
  Also assigns it on the LiveView socket via the session.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    demo_mode = get_session(conn, :demo_mode) == true
    assign(conn, :demo_mode, demo_mode)
  end
end
