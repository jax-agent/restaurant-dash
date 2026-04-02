defmodule RestaurantDashWeb.Plugs.CaptureRawBody do
  @moduledoc """
  Custom body reader for Plug.Parsers.
  Caches the raw request body in conn.assigns[:raw_body] before parsing.

  This is required for Stripe webhook signature verification, which needs
  the exact bytes of the request body.

  Usage in endpoint.ex Plug.Parsers:
    body_reader: {RestaurantDashWeb.Plugs.CaptureRawBody, :read_body, []}
  """

  @doc "Body reader that caches raw body in conn.assigns[:raw_body]."
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.assign(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
