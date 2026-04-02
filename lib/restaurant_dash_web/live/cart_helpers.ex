defmodule RestaurantDashWeb.CartHelpers do
  @moduledoc """
  Helper functions for managing cart state in LiveViews.

  Usage in a LiveView:
    - Call `mount_cart(socket, session)` in `mount/3` to load the cart
    - Call `put_cart(socket, cart)` to update the cart in assigns + store
    - Access cart via `socket.assigns.cart`
  """

  alias RestaurantDash.Cart
  alias RestaurantDash.Cart.Store

  @cart_session_key "cart_id"

  @doc """
  Load (or create) the cart for this session.
  Assigns :cart and :cart_id to the socket.
  """
  def mount_cart(socket, session, restaurant_id \\ nil) do
    cart_id = session[@cart_session_key] || generate_cart_id()
    cart = Store.get(cart_id, restaurant_id)

    socket
    |> Phoenix.Component.assign(:cart_id, cart_id)
    |> Phoenix.Component.assign(:cart, cart)
    |> Phoenix.Component.assign(:cart_drawer_open, false)
  end

  @doc """
  Update the cart in both the store and socket assigns.
  Returns the updated socket.
  """
  def put_cart(socket, %Cart{} = cart) do
    cart_id = socket.assigns.cart_id
    Store.put(cart_id, cart)

    socket
    |> Phoenix.Component.assign(:cart, cart)
  end

  @doc """
  Clear the cart from store and reset assigns.
  """
  def clear_cart(socket) do
    Store.delete(socket.assigns.cart_id)
    restaurant_id = get_in(socket.assigns, [:cart, Access.key(:restaurant_id)])
    put_cart(socket, Cart.new(restaurant_id))
  end

  defp generate_cart_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
