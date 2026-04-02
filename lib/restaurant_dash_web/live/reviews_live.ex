defmodule RestaurantDashWeb.ReviewsLive do
  @moduledoc "Public reviews page for a restaurant. Also used by owner to respond."
  use RestaurantDashWeb, :live_view

  alias RestaurantDash.{Orders, Tenancy}

  @impl true
  def mount(params, session, socket) do
    restaurant =
      case session["current_restaurant"] do
        %{} = r ->
          r

        _ ->
          case params["restaurant_slug"] do
            nil -> nil
            slug -> Tenancy.get_restaurant_by_slug(slug)
          end
      end

    if is_nil(restaurant) do
      {:ok, assign(socket, :restaurant, nil)}
    else
      {avg, count} = Orders.get_restaurant_rating(restaurant.id)
      reviews = Orders.list_reviews(restaurant.id)

      {:ok,
       socket
       |> assign(:restaurant, restaurant)
       |> assign(:reviews, reviews)
       |> assign(:avg_rating, avg)
       |> assign(:review_count, count)
       |> assign(:responding_to, nil)
       |> assign(:response_text, "")}
    end
  end

  @impl true
  def handle_event("start-respond", %{"id" => id}, socket) do
    {:noreply, assign(socket, responding_to: String.to_integer(id), response_text: "")}
  end

  @impl true
  def handle_event("cancel-respond", _, socket) do
    {:noreply, assign(socket, responding_to: nil)}
  end

  @impl true
  def handle_event("update-response", %{"value" => value}, socket) do
    {:noreply, assign(socket, response_text: value)}
  end

  @impl true
  def handle_event("submit-response", _, socket) do
    order_id = socket.assigns.responding_to
    order = Orders.get_order!(order_id)

    case Orders.respond_to_review(order, socket.assigns.response_text) do
      {:ok, _} ->
        reviews = Orders.list_reviews(socket.assigns.restaurant.id)
        {:noreply, assign(socket, reviews: reviews, responding_to: nil, response_text: "")}

      _ ->
        {:noreply, socket}
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  defp stars(rating) when is_integer(rating) do
    String.duplicate("★", rating) <> String.duplicate("☆", 5 - rating)
  end

  defp stars(_), do: "☆☆☆☆☆"

  defp format_date(nil), do: ""

  defp format_date(%DateTime{} = dt) do
    "#{dt.month}/#{dt.day}/#{dt.year}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <%= if @restaurant do %>
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-gray-900">{@restaurant.name}</h1>
          <p class="text-xl font-semibold mt-2">
            <span class="text-yellow-500">
              {if @avg_rating, do: stars(round(@avg_rating)), else: "No reviews yet"}
            </span>
            <%= if @avg_rating do %>
              <span class="text-gray-700 text-base ml-2">
                {Float.round(@avg_rating, 1)}/5 ({@review_count} review{if @review_count != 1, do: "s"})
              </span>
            <% end %>
          </p>
        </div>

        <%= if Enum.empty?(@reviews) do %>
          <div class="bg-gray-50 border border-gray-200 rounded-xl p-8 text-center text-gray-500">
            No reviews yet. Be the first to review!
          </div>
        <% else %>
          <div class="space-y-4">
            <%= for review <- @reviews do %>
              <div class="bg-white border border-gray-200 rounded-xl p-4">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-yellow-500 text-lg">{stars(review.restaurant_rating)}</span>
                  <span class="text-gray-400 text-sm">{format_date(review.delivered_at)}</span>
                </div>

                <%= if review.restaurant_review && review.restaurant_review != "" do %>
                  <p class="text-gray-700">{review.restaurant_review}</p>
                <% end %>

                <p class="text-gray-500 text-sm mt-1">{review.customer_name}</p>

                <%= if review.review_response do %>
                  <div class="mt-3 bg-gray-50 rounded-lg p-3 border-l-4 border-indigo-300">
                    <p class="text-xs font-medium text-indigo-600 mb-1">Owner Response:</p>
                    <p class="text-gray-700 text-sm">{review.review_response}</p>
                  </div>
                <% end %>

                <%!-- Owner respond button (if logged in as owner) --%>
                <%= if is_nil(review.review_response) do %>
                  <%= if @responding_to == review.id do %>
                    <div class="mt-3">
                      <textarea
                        phx-blur="update-response"
                        class="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm"
                        placeholder="Write your response..."
                        rows="3"
                      ><%= @response_text %></textarea>
                      <div class="flex gap-2 mt-2">
                        <button
                          phx-click="submit-response"
                          class="bg-indigo-600 text-white px-3 py-1 rounded text-sm hover:bg-indigo-700"
                        >
                          Submit
                        </button>
                        <button phx-click="cancel-respond" class="text-gray-500 text-sm">
                          Cancel
                        </button>
                      </div>
                    </div>
                  <% else %>
                    <button
                      phx-click="start-respond"
                      phx-value-id={review.id}
                      class="text-indigo-600 text-sm mt-2 hover:text-indigo-800"
                    >
                      Respond
                    </button>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      <% else %>
        <div class="text-center py-12 text-gray-500">
          <p>Restaurant not found.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
