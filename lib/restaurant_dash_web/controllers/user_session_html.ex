defmodule RestaurantDashWeb.UserSessionHTML do
  use RestaurantDashWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:restaurant_dash, RestaurantDash.Mailer)[:adapter] ==
      Swoosh.Adapters.Local
  end
end
