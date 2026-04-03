defmodule RestaurantDashWeb.LandingLive do
  @moduledoc """
  Public landing page shown at the root URL when no restaurant context is detected
  and the user is not logged in.
  """
  use RestaurantDashWeb, :live_view

  on_mount {RestaurantDashWeb.UserAuth, :mount_current_user}

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    # If user is logged in as owner, redirect to their dashboard
    if current_user && current_user.role in ~w(owner staff) do
      {:ok, redirect(socket, to: ~p"/dashboard")}
    else
      {:ok, assign(socket, :current_user, current_user)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="background:#0A0A0A;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
      <%!-- Hero --%>
      <div style="background:linear-gradient(180deg,#111 0%,#0A0A0A 100%);">
        <nav style="max-width:1200px;margin:0 auto;padding:24px 24px;display:flex;align-items:center;justify-content:space-between;">
          <div style="display:flex;align-items:center;gap:12px;">
            <img src="/images/logo.png" alt="Order Base" style="width:32px;height:32px;border-radius:8px;" />
            <span style="color:white;font-weight:600;font-size:18px;">Order Base</span>
          </div>
          <div style="display:flex;align-items:center;gap:16px;">
            <a href="/users/log-in" style="color:#666;font-size:14px;font-weight:500;text-decoration:none;">Sign in</a>
            <a href="/demo" style="background:#E63946;color:white;font-weight:600;padding:10px 20px;border-radius:8px;font-size:14px;text-decoration:none;">Try Demo</a>
          </div>
        </nav>

        <div style="max-width:800px;margin:0 auto;padding:80px 24px 120px;text-align:center;">
          <h1 style="color:white;font-size:clamp(36px,5vw,64px);font-weight:700;line-height:1.1;letter-spacing:-0.03em;margin-bottom:24px;">
            Run your own<br /><span style="color:#E63946;">delivery business.</span>
          </h1>
          <p style="color:#666;font-size:18px;max-width:520px;margin:0 auto 40px;line-height:1.6;">
            The all-in-one platform for restaurants to own their delivery. No middlemen. No commissions.
          </p>
          <div style="display:flex;gap:16px;justify-content:center;flex-wrap:wrap;">
            <a href="/demo" style="background:#E63946;color:white;font-weight:600;padding:16px 32px;border-radius:12px;font-size:16px;box-shadow:0 4px 20px rgba(230,57,70,0.3);text-decoration:none;">Try the Demo →</a>
            <a href="/signup" style="background:transparent;border:1px solid #333;color:white;font-weight:600;padding:16px 32px;border-radius:12px;font-size:16px;text-decoration:none;">Start free</a>
          </div>
        </div>
      </div>

      <%!-- Features --%>
      <div style="padding:80px 24px;background:#0A0A0A;">
        <div style="max-width:1000px;margin:0 auto;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px;">
          <div style="background:#111;border:1px solid #222;border-radius:16px;padding:32px;">
            <div style="font-size:28px;margin-bottom:16px;">📋</div>
            <h3 style="color:white;font-weight:600;font-size:18px;margin-bottom:8px;">Order Management</h3>
            <p style="color:#666;font-size:14px;line-height:1.6;">Real-time Kanban. Move orders through status. Kitchen display built in.</p>
          </div>
          <div style="background:#111;border:1px solid #222;border-radius:16px;padding:32px;">
            <div style="font-size:28px;margin-bottom:16px;">🗺️</div>
            <h3 style="color:white;font-weight:600;font-size:18px;margin-bottom:8px;">Live Tracking</h3>
            <p style="color:#666;font-size:14px;line-height:1.6;">Track drivers on a map. Customers see their order in real-time.</p>
          </div>
          <div style="background:#111;border:1px solid #222;border-radius:16px;padding:32px;">
            <div style="font-size:28px;margin-bottom:16px;">🎨</div>
            <h3 style="color:white;font-weight:600;font-size:18px;margin-bottom:8px;">Your Brand</h3>
            <p style="color:#666;font-size:14px;line-height:1.6;">White-label. Your colors. Your logo. Customers see you, not us.</p>
          </div>
        </div>
      </div>

      <%!-- CTA --%>
      <div style="background:#111;border-top:1px solid #222;padding:80px 24px;text-align:center;">
        <h2 style="color:white;font-weight:600;font-size:28px;margin-bottom:12px;">Ready?</h2>
        <p style="color:#666;margin-bottom:32px;">Set up in 5 minutes. No credit card.</p>
        <a href="/demo" style="background:#E63946;color:white;font-weight:600;padding:16px 40px;border-radius:12px;font-size:16px;display:inline-block;text-decoration:none;">Try Demo Now →</a>
      </div>

      <%!-- Footer --%>
      <footer style="background:#0A0A0A;border-top:1px solid #222;padding:40px 24px;text-align:center;">
        <p style="color:#444;font-size:14px;">© 2026 Order Base. Built for Puerto Rico.</p>
      </footer>
    </div>
    """
  end

  defp get_current_user(socket) do
    case socket.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end
end
