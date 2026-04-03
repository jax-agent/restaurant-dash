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
    <div class="min-h-screen bg-white">
      <%!-- Hero Section --%>
      <header class="bg-gradient-to-br from-red-500 to-orange-400 text-white">
        <div class="max-w-6xl mx-auto px-6 py-6 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <%!-- Order Base logo: coral-red rounded square with O↗ --%>
            <span style="background:#E63946;border-radius:8px;width:36px;height:36px;display:inline-flex;align-items:center;justify-content:center;font-weight:900;font-size:15px;color:#fff;flex-shrink:0;">
              O↗
            </span>
            <span class="text-xl font-bold">Order Base</span>
          </div>
          <nav class="flex items-center gap-4 text-sm">
            <a href="/users/log-in" class="hover:text-red-100 font-medium">Log in</a>
            <a
              href="/demo"
              class="border-2 border-white text-white hover:bg-white/20 font-semibold px-4 py-2 rounded-lg transition-colors"
            >
              Try Demo →
            </a>
            <a
              href="/signup"
              class="bg-white text-red-500 hover:bg-red-50 font-semibold px-4 py-2 rounded-lg transition-colors"
            >
              Get Started
            </a>
          </nav>
        </div>

        <div class="max-w-4xl mx-auto px-6 py-24 text-center">
          <h1 class="text-5xl font-bold leading-tight mb-6">
            Launch Your Own <br />Delivery Platform
          </h1>
          <p class="text-xl text-red-100 mb-10 max-w-2xl mx-auto">
            Order Base gives you everything you need to manage orders, track deliveries,
            and grow your restaurant — all in one place.
          </p>
          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="/signup"
              class="bg-white text-red-500 hover:bg-red-50 font-bold px-8 py-4 rounded-xl text-lg transition-colors shadow-lg"
            >
              Start for Free →
            </a>
            <a
              href="/demo"
              class="bg-red-600/80 hover:bg-red-700/80 border-2 border-white/30 text-white font-bold px-8 py-4 rounded-xl text-lg transition-colors shadow-lg"
            >
              🎯 Try Demo
            </a>
            <a
              href="/users/log-in"
              class="border-2 border-white text-white hover:bg-white/10 font-bold px-8 py-4 rounded-xl text-lg transition-colors"
            >
              Log in
            </a>
          </div>
          <p class="mt-4 text-red-200 text-sm">No signup required for demo · Full dashboard access</p>
        </div>
      </header>

      <%!-- Features Section --%>
      <section class="py-24 bg-gray-50">
        <div class="max-w-6xl mx-auto px-6">
          <h2 class="text-3xl font-bold text-center text-gray-900 mb-4">
            Everything your restaurant needs
          </h2>
          <p class="text-gray-500 text-center mb-16 max-w-xl mx-auto">
            Built for independent restaurants who want to own their delivery operation — no middlemen, no commissions.
          </p>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
            <div class="bg-white rounded-2xl p-8 shadow-sm border border-gray-100">
              <div class="text-4xl mb-4">📋</div>
              <h3 class="text-xl font-bold text-gray-900 mb-2">Order Management</h3>
              <p class="text-gray-500">
                Real-time Kanban board. Move orders from new → preparing → out for delivery → done.
              </p>
            </div>

            <div class="bg-white rounded-2xl p-8 shadow-sm border border-gray-100">
              <div class="text-4xl mb-4">🗺️</div>
              <h3 class="text-xl font-bold text-gray-900 mb-2">Live Delivery Tracking</h3>
              <p class="text-gray-500">
                Track your drivers on a live map. Know exactly where every delivery is at all times.
              </p>
            </div>

            <div class="bg-white rounded-2xl p-8 shadow-sm border border-gray-100">
              <div class="text-4xl mb-4">🎨</div>
              <h3 class="text-xl font-bold text-gray-900 mb-2">Your Brand, Your Platform</h3>
              <p class="text-gray-500">
                White-label your storefront with your colors and logo. Customers see your brand, not ours.
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- CTA Section --%>
      <section class="py-20 bg-red-500 text-white text-center">
        <div class="max-w-2xl mx-auto px-6">
          <h2 class="text-3xl font-bold mb-4">Ready to launch?</h2>
          <p class="text-red-100 mb-8 text-lg">
            Set up your restaurant in under 5 minutes. No credit card required.
          </p>
          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="/signup"
              class="bg-white text-red-500 hover:bg-red-50 font-bold px-10 py-4 rounded-xl text-lg inline-block transition-colors shadow-lg"
            >
              Create Your Restaurant →
            </a>
            <a
              href="/demo"
              class="border-2 border-white text-white hover:bg-white/10 font-bold px-10 py-4 rounded-xl text-lg inline-block transition-colors"
            >
              🎯 Explore Demo First
            </a>
          </div>
        </div>
      </section>

      <footer class="bg-gray-900 text-gray-400 py-8 text-center text-sm">
        <p>© 2026 Order Base. Built for independent restaurants.</p>
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
