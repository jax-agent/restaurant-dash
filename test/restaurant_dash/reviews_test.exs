defmodule RestaurantDash.ReviewsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Orders
  alias RestaurantDash.Tenancy

  defp restaurant_fixture do
    slug = "review-test-#{System.unique_integer([:positive])}"

    {:ok, r} =
      Tenancy.create_restaurant(%{name: "Review Test", slug: slug, timezone: "America/Chicago"})

    r
  end

  defp delivered_order_fixture(restaurant_id) do
    {:ok, order} =
      %RestaurantDash.Orders.Order{}
      |> RestaurantDash.Orders.Order.cart_order_changeset(%{
        customer_name: "Reviewer",
        customer_email: "reviewer@example.com",
        customer_phone: "555-1111",
        delivery_address: "1 Review Lane",
        restaurant_id: restaurant_id,
        status: "delivered"
      })
      |> RestaurantDash.Repo.insert()

    order
  end

  describe "submit_restaurant_review/3" do
    test "submits a rating and review" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)
      assert {:ok, updated} = Orders.submit_restaurant_review(order, 5, "Excellent food!")
      assert updated.restaurant_rating == 5
      assert updated.restaurant_review == "Excellent food!"
    end

    test "rejects rating outside 1-5" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)
      assert {:error, changeset} = Orders.submit_restaurant_review(order, 6, "Too good")
      assert errors_on(changeset).restaurant_rating != []
    end

    test "sanitizes HTML from review text" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)

      {:ok, updated} =
        Orders.submit_restaurant_review(order, 4, "<script>alert('xss')</script>Great!")

      refute String.contains?(updated.restaurant_review, "<script>")
      assert String.contains?(updated.restaurant_review, "Great!")
    end

    test "allows empty review text" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)
      assert {:ok, updated} = Orders.submit_restaurant_review(order, 3)
      assert updated.restaurant_rating == 3
      # review may be nil or empty string when no text provided
      assert updated.restaurant_review in ["", nil]
    end
  end

  describe "respond_to_review/2" do
    test "owner can respond to a review" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)
      {:ok, reviewed} = Orders.submit_restaurant_review(order, 4, "Good food")

      assert {:ok, responded} =
               Orders.respond_to_review(reviewed, "Thank you for the kind words!")

      assert responded.review_response == "Thank you for the kind words!"
    end
  end

  describe "get_restaurant_rating/1" do
    test "returns average rating and count" do
      restaurant = restaurant_fixture()
      order1 = delivered_order_fixture(restaurant.id)
      order2 = delivered_order_fixture(restaurant.id)
      Orders.submit_restaurant_review(order1, 4, "Good")
      Orders.submit_restaurant_review(order2, 2, "Meh")

      {avg, count} = Orders.get_restaurant_rating(restaurant.id)
      assert count == 2
      assert_in_delta avg, 3.0, 0.1
    end

    test "returns nil, 0 for no reviews" do
      restaurant = restaurant_fixture()
      assert {nil, 0} = Orders.get_restaurant_rating(restaurant.id)
    end
  end

  describe "list_reviews/1" do
    test "returns orders with ratings" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)
      {:ok, reviewed} = Orders.submit_restaurant_review(order, 5, "Amazing!")

      reviews = Orders.list_reviews(restaurant.id)
      assert Enum.any?(reviews, &(&1.id == reviewed.id))
    end

    test "excludes orders without reviews" do
      restaurant = restaurant_fixture()
      order = delivered_order_fixture(restaurant.id)
      reviews = Orders.list_reviews(restaurant.id)
      refute Enum.any?(reviews, &(&1.id == order.id))
    end
  end
end
