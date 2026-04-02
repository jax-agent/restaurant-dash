defmodule RestaurantDash.Notifications.EmailTest do
  use RestaurantDash.DataCase, async: true

  import Swoosh.TestAssertions

  alias RestaurantDash.Notifications.Email
  alias RestaurantDash.Workers.EmailNotificationWorker
  alias RestaurantDash.Notifications

  # ─── Helpers ───────────────────────────────────────────────────────────────

  defp restaurant_fixture do
    {:ok, r} =
      RestaurantDash.Tenancy.create_restaurant(%{
        name: "Email Kitchen",
        slug: "email-kitchen-#{System.unique_integer([:positive])}",
        address: "1 Test",
        city: "SF",
        state: "CA",
        zip: "94000",
        primary_color: "#3B82F6"
      })

    r
  end

  defp order_fixture(restaurant) do
    %RestaurantDash.Orders.Order{}
    |> Ecto.Changeset.cast(
      %{
        customer_name: "Email Tester",
        customer_email: "tester@example.com",
        customer_phone: "+15551234567",
        delivery_address: "99 Test Ave",
        items: ["Burger"],
        status: "new",
        restaurant_id: restaurant.id,
        subtotal: 1200,
        tax_amount: 100,
        delivery_fee: 299,
        total_amount: 1599
      },
      [
        :customer_name,
        :customer_email,
        :customer_phone,
        :delivery_address,
        :items,
        :status,
        :restaurant_id,
        :subtotal,
        :tax_amount,
        :delivery_fee,
        :total_amount
      ]
    )
    |> RestaurantDash.Repo.insert!()
  end

  # ─── Email Builders ────────────────────────────────────────────────────────

  describe "Email.order_confirmed/2" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "builds email with correct to/from/subject", %{order: order, restaurant: restaurant} do
      email = Email.order_confirmed(order, restaurant)

      assert email.subject =~ "Order Confirmed"
      assert email.subject =~ to_string(order.id)
      assert email.html_body =~ "Email Tester"
      assert email.html_body =~ "Email Kitchen"
      assert email.html_body =~ "#3B82F6"
    end

    test "includes tracking URL in html body", %{order: order, restaurant: restaurant} do
      email = Email.order_confirmed(order, restaurant)
      assert email.html_body =~ "/orders/#{order.id}/track"
    end

    test "includes text body fallback", %{order: order, restaurant: restaurant} do
      email = Email.order_confirmed(order, restaurant)
      assert email.text_body =~ "confirmed"
    end

    test "works without restaurant (nil)", %{order: order} do
      email = Email.order_confirmed(order, nil)
      assert email.subject =~ "Order Confirmed"
      assert is_binary(email.html_body)
    end
  end

  describe "Email.delivery_update/3" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "builds update email", %{order: order, restaurant: restaurant} do
      email = Email.delivery_update(order, restaurant, "Out for Delivery")
      assert email.subject =~ "Update"
      assert email.html_body =~ "Out for Delivery"
    end
  end

  describe "Email.welcome/4" do
    test "builds welcome email for customer" do
      email = Email.welcome("alice@example.com", "Alice", "customer", "Great Eats")
      assert email.subject =~ "Welcome"
      assert email.html_body =~ "Alice"
      assert email.html_body =~ "Great Eats"
    end

    test "works with default restaurant name" do
      email = Email.welcome("bob@example.com", "Bob", "driver")
      assert is_binary(email.html_body)
    end
  end

  # ─── Email delivery (Swoosh Test adapter) ─────────────────────────────────

  describe "Email.deliver/1" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "delivers email via test adapter", %{order: order, restaurant: restaurant} do
      email = Email.order_confirmed(order, restaurant)
      assert {:ok, _} = Email.deliver(email)
      assert_email_sent(subject: "Order Confirmed — ##{order.id}")
    end

    test "welcome email delivers successfully" do
      email = Email.welcome("test@example.com", "Test User", "owner")
      assert {:ok, _} = Email.deliver(email)
      assert_email_sent(subject: ~r/Welcome/)
    end
  end

  # ─── EmailNotificationWorker ───────────────────────────────────────────────

  describe "EmailNotificationWorker.perform/1" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "sends confirmation email and creates notification record", %{
      restaurant: restaurant,
      order: order
    } do
      job = %Oban.Job{
        args: %{
          "order_id" => order.id,
          "restaurant_id" => restaurant.id,
          "template" => "email:order_confirmed"
        }
      }

      assert :ok = EmailNotificationWorker.perform(job)

      # Assert Swoosh test adapter received email
      assert_email_sent(subject: ~r/Order Confirmed/)

      # Assert notification record created and marked sent
      notifications = Notifications.list_notifications(restaurant.id, channel: "email")
      assert length(notifications) == 1
      assert hd(notifications).status == "sent"
    end

    test "returns :ok for missing order" do
      job = %Oban.Job{
        args: %{
          "order_id" => 999_999,
          "restaurant_id" => 1,
          "template" => "email:order_confirmed"
        }
      }

      assert :ok = EmailNotificationWorker.perform(job)
    end

    test "enqueue/3 creates Oban job" do
      assert {:ok, job} = EmailNotificationWorker.enqueue(1, 2, "email:order_confirmed")
      assert job.args["template"] == "email:order_confirmed"
    end
  end
end
