defmodule RestaurantDash.Notifications.Email do
  @moduledoc """
  Email notification builder using Swoosh.

  Builds and sends transactional emails (order confirmation, delivery updates, welcome).
  In dev/test uses Swoosh.Adapters.Local / Test adapters.
  """

  import Swoosh.Email
  alias RestaurantDash.Mailer

  @from_name "Order Base"
  @from_email "notifications@restaurantdash.app"

  # ─── Email Builders ───────────────────────────────────────────────────────

  @doc """
  Order confirmation email with itemized receipt.
  """
  def order_confirmed(order, restaurant) do
    restaurant_name = (restaurant && restaurant.name) || "Restaurant"
    primary_color = (restaurant && restaurant.primary_color) || "#E63946"
    tracking_url = build_tracking_url(order)

    new()
    |> to({order.customer_name || "Customer", order.customer_email})
    |> from({restaurant_name, @from_email})
    |> subject("Order Confirmed — ##{order.id}")
    |> html_body(order_confirmed_html(order, restaurant_name, primary_color, tracking_url))
    |> text_body(order_confirmed_text(order, restaurant_name, tracking_url))
  end

  @doc """
  Delivery status update email.
  """
  def delivery_update(order, restaurant, status_label) do
    restaurant_name = (restaurant && restaurant.name) || "Restaurant"
    primary_color = (restaurant && restaurant.primary_color) || "#E63946"
    tracking_url = build_tracking_url(order)

    new()
    |> to({order.customer_name || "Customer", order.customer_email})
    |> from({restaurant_name, @from_email})
    |> subject("Update on Your Order ##{order.id}: #{status_label}")
    |> html_body(
      delivery_update_html(order, restaurant_name, primary_color, status_label, tracking_url)
    )
    |> text_body(
      "Hi #{order.customer_name},\n\nYour order ##{order.id} is now: #{status_label}.\n\nTrack it: #{tracking_url}"
    )
  end

  @doc """
  Welcome email for new customers/drivers/owners.
  """
  def welcome(email, name, role, restaurant_name \\ "Order Base") do
    new()
    |> to({name, email})
    |> from({@from_name, @from_email})
    |> subject("Welcome to #{restaurant_name}!")
    |> html_body(welcome_html(name, role, restaurant_name))
    |> text_body("Welcome, #{name}! Your #{role} account for #{restaurant_name} is ready.")
  end

  # ─── Delivery ────────────────────────────────────────────────────────────

  @doc "Send an email (delegates to Mailer)."
  def deliver(email) do
    Mailer.deliver(email)
  end

  # ─── HTML Templates ───────────────────────────────────────────────────────

  defp order_confirmed_html(order, restaurant_name, primary_color, tracking_url) do
    items_html = build_items_html(order)
    totals_html = build_totals_html(order)

    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>Order Confirmed</title></head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8f8f8; margin: 0; padding: 20px;">
      <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.08);">
        <div style="background: #{primary_color}; padding: 32px 24px; text-align: center;">
          <h1 style="color: white; margin: 0; font-size: 24px;">#{restaurant_name}</h1>
          <p style="color: rgba(255,255,255,0.8); margin: 8px 0 0; font-size: 14px;">Order Confirmation</p>
        </div>
        <div style="padding: 32px 24px;">
          <h2 style="color: #1a1a1a; font-size: 20px; margin: 0 0 8px;">Order Confirmed! 🎉</h2>
          <p style="color: #666; font-size: 14px; margin: 0 0 24px;">
            Hi #{order.customer_name}, your order ##{order.id} has been received.
          </p>

          <div style="background: #f8f8f8; border-radius: 8px; padding: 16px; margin-bottom: 24px;">
            <h3 style="margin: 0 0 12px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px; color: #888;">Your Items</h3>
            #{items_html}
            #{totals_html}
          </div>

          #{if order.delivery_address do
      """
      <div style="margin-bottom: 24px;">
        <h3 style="margin: 0 0 8px; font-size: 14px; color: #888; text-transform: uppercase;">Delivery To</h3>
        <p style="margin: 0; color: #333; font-size: 14px;">#{order.delivery_address}</p>
      </div>
      """
    else
      ""
    end}

          <a href="#{tracking_url}" style="display: block; background: #{primary_color}; color: white; text-align: center; padding: 14px 24px; border-radius: 8px; text-decoration: none; font-weight: 600; font-size: 15px;">
            Track Your Order
          </a>

          <p style="margin: 24px 0 0; color: #999; font-size: 12px; text-align: center;">
            Estimated delivery time: 30–45 minutes
          </p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp delivery_update_html(order, restaurant_name, primary_color, status_label, tracking_url) do
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>Order Update</title></head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8f8f8; margin: 0; padding: 20px;">
      <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.08);">
        <div style="background: #{primary_color}; padding: 32px 24px; text-align: center;">
          <h1 style="color: white; margin: 0; font-size: 24px;">#{restaurant_name}</h1>
        </div>
        <div style="padding: 32px 24px; text-align: center;">
          <h2 style="color: #1a1a1a; font-size: 20px;">#{status_label}</h2>
          <p style="color: #666; font-size: 14px;">Order ##{order.id} update</p>
          <a href="#{tracking_url}" style="display: inline-block; background: #{primary_color}; color: white; padding: 12px 28px; border-radius: 8px; text-decoration: none; font-weight: 600; margin-top: 16px;">
            Track Live
          </a>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp welcome_html(name, role, restaurant_name) do
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>Welcome!</title></head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8f8f8; margin: 0; padding: 20px;">
      <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; padding: 40px 32px; text-align: center; box-shadow: 0 2px 8px rgba(0,0,0,0.08);">
        <h1 style="color: #1a1a1a;">Welcome to #{restaurant_name}! 🎉</h1>
        <p style="color: #666; font-size: 15px;">Hi #{name}, your #{role} account is ready.</p>
      </div>
    </body>
    </html>
    """
  end

  defp order_confirmed_text(order, restaurant_name, tracking_url) do
    """
    Order Confirmed — ##{order.id}

    Hi #{order.customer_name},

    Your order from #{restaurant_name} has been confirmed!

    Track your order: #{tracking_url}

    Estimated delivery: 30-45 minutes.
    """
  end

  defp build_items_html(%{order_items: items}) when is_list(items) and length(items) > 0 do
    items
    |> Enum.map(fn item ->
      price = format_price(item.line_total)

      """
      <div style="display: flex; justify-content: space-between; padding: 6px 0; font-size: 14px; color: #333;">
        <span>×#{item.quantity} #{item.name}</span>
        <span style="font-weight: 600;">#{price}</span>
      </div>
      """
    end)
    |> Enum.join("\n")
  end

  defp build_items_html(_), do: ""

  defp build_totals_html(%{total_amount: total} = order) when total > 0 do
    """
    <hr style="border: none; border-top: 1px solid #eee; margin: 12px 0;">
    <div style="display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px; color: #888;">
      <span>Subtotal</span><span>#{format_price(order.subtotal)}</span>
    </div>
    <div style="display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px; color: #888;">
      <span>Tax</span><span>#{format_price(order.tax_amount)}</span>
    </div>
    <div style="display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px; color: #888;">
      <span>Delivery</span><span>#{format_price(order.delivery_fee)}</span>
    </div>
    <div style="display: flex; justify-content: space-between; padding: 8px 0 0; font-size: 15px; font-weight: 700; color: #1a1a1a;">
      <span>Total</span><span>#{format_price(order.total_amount)}</span>
    </div>
    """
  end

  defp build_totals_html(_), do: ""

  defp build_tracking_url(order) do
    host =
      Application.get_env(:restaurant_dash, RestaurantDashWeb.Endpoint, [])
      |> Keyword.get(:url, [])
      |> Keyword.get(:host, "localhost")

    "https://#{host}/orders/#{order.id}/track"
  end

  defp format_price(nil), do: "$0.00"
  defp format_price(0), do: "$0.00"

  defp format_price(cents) when is_integer(cents) do
    "$#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end
end
