defmodule RestaurantDashWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix channels.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import RestaurantDashWeb.ChannelCase

      # The default endpoint for testing
      @endpoint RestaurantDashWeb.Endpoint
    end
  end

  setup tags do
    RestaurantDash.DataCase.setup_sandbox(tags)
    :ok
  end
end
