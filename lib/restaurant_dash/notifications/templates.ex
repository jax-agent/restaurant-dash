defmodule RestaurantDash.Notifications.Templates do
  @moduledoc """
  Predefined notification templates for the order lifecycle.

  Templates use double-brace variable syntax for interpolation, e.g. variable_name wrapped in braces.
  The ~S sigil is used on templates to prevent Elixir from interpreting hash-brace sequences.
  """

  # ~S disables Elixir string interpolation so #{{order_number}} stays literal
  @templates %{
    # ─── SMS Templates ──────────────────────────────────────────────────────
    "sms:order_confirmed" =>
      ~S"Hi {{customer_name}}! Your order #{{order_number}} from {{restaurant_name}} is confirmed. Estimated delivery: {{eta}}. Track at: {{tracking_url}}",
    "sms:order_preparing" =>
      ~S"{{restaurant_name}}: Your order #{{order_number}} is being prepared by the kitchen!",
    "sms:out_for_delivery" =>
      ~S"Your order #{{order_number}} from {{restaurant_name}} is on the way! Driver: {{driver_name}}. Track live: {{tracking_url}}",
    "sms:delivered" =>
      ~S"Your order #{{order_number}} has been delivered. Enjoy your meal! Rate your experience: {{tracking_url}}",
    "sms:driver_assigned" =>
      ~S"New delivery assigned: Order #{{order_number}} from {{restaurant_name}}. Customer: {{customer_name}}, Address: {{delivery_address}}",

    # ─── Email Templates (subject lines) ────────────────────────────────────
    "email:order_confirmed" => ~S"Order Confirmed — #{{order_number}}",
    "email:delivery_update" => ~S"Update on Your Order #{{order_number}}",
    "email:welcome_customer" => ~S"Welcome to {{restaurant_name}}!",
    "email:welcome_driver" => ~S"Welcome to the {{restaurant_name}} Driver Team!",
    "email:welcome_owner" => "Your Order Base account is ready!",

    # ─── In-App Templates ───────────────────────────────────────────────────
    "in_app:new_order" => ~S"New order #{{order_number}} received! ({{total}})",
    "in_app:driver_assigned" => ~S"Driver {{driver_name}} assigned to order #{{order_number}}",
    "in_app:payment_received" => ~S"Payment of {{total}} received for order #{{order_number}}",
    "in_app:low_rating_alert" => ~S"Order #{{order_number}} received a {{rating}}-star rating",
    "in_app:delivery_assigned" =>
      ~S"New delivery: Order #{{order_number}} from {{restaurant_name}}",
    "in_app:delivery_cancelled" =>
      ~S"Delivery cancelled: Order #{{order_number}} has been cancelled"
  }

  @doc """
  Render a template by key with the given variable bindings.
  Returns {:ok, rendered_string} or {:error, reason}.
  """
  def render(template_key, vars \\ %{}) do
    case Map.get(@templates, template_key) do
      nil ->
        {:error, "Template not found: #{template_key}"}

      template ->
        rendered =
          Enum.reduce(vars, template, fn {key, value}, acc ->
            String.replace(acc, "{{#{key}}}", to_string(value))
          end)
          |> String.trim()

        {:ok, rendered}
    end
  end

  @doc "Get the raw template string."
  def get_template(key), do: Map.get(@templates, key)

  @doc "List all available template keys."
  def list_templates, do: Map.keys(@templates)

  @doc "List templates for a given channel (sms, email, in_app)."
  def list_templates(channel) do
    prefix = "#{channel}:"

    @templates
    |> Enum.filter(fn {k, _} -> String.starts_with?(k, prefix) end)
    |> Enum.map(fn {k, _} -> k end)
  end
end
