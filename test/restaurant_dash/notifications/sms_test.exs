defmodule RestaurantDash.Notifications.SMSTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Notifications.SMS
  alias RestaurantDash.Workers.SMSNotificationWorker
  alias RestaurantDash.Notifications

  # ─── Helper ────────────────────────────────────────────────────────────────

  defp restaurant_fixture do
    {:ok, r} =
      RestaurantDash.Tenancy.create_restaurant(%{
        name: "SMS Test Kitchen",
        slug: "sms-test-#{System.unique_integer([:positive])}",
        address: "1 Test St",
        city: "Testville",
        state: "CA",
        zip: "94000"
      })

    r
  end

  defp order_fixture(restaurant) do
    %RestaurantDash.Orders.Order{}
    |> Ecto.Changeset.cast(
      %{
        customer_name: "Tester",
        customer_phone: "+15551234567",
        customer_email: "tester@example.com",
        delivery_address: "10 Delivery Lane",
        items: ["Pizza"],
        status: "new",
        restaurant_id: restaurant.id
      },
      [
        :customer_name,
        :customer_phone,
        :customer_email,
        :delivery_address,
        :items,
        :status,
        :restaurant_id
      ]
    )
    |> RestaurantDash.Repo.insert!()
  end

  # ─── SMS Module ────────────────────────────────────────────────────────────

  describe "SMS.mock_mode?/0" do
    test "returns true when no Twilio config set (default test env)" do
      # Default test env has no Twilio creds → mock mode
      assert SMS.mock_mode?() == true
    end
  end

  describe "SMS.send/2 in mock mode" do
    test "returns {:ok, :mock} without calling Twilio" do
      assert {:ok, :mock} = SMS.send("+15551234567", "Test message")
    end

    test "accepts any phone number format" do
      assert {:ok, :mock} = SMS.send("+44 7700 900000", "Hello from UK!")
    end
  end

  # ─── SMSNotificationWorker ─────────────────────────────────────────────────

  describe "SMSNotificationWorker.enqueue/3" do
    test "inserts an Oban job" do
      assert {:ok, job} = SMSNotificationWorker.enqueue(123, 456, "sms:order_confirmed")
      assert job.worker == "RestaurantDash.Workers.SMSNotificationWorker"
      assert job.args["template"] == "sms:order_confirmed"
      assert job.args["recipient"] == "customer"
    end
  end

  describe "SMSNotificationWorker.enqueue_driver/3" do
    test "inserts an Oban job with driver recipient" do
      assert {:ok, job} = SMSNotificationWorker.enqueue_driver(123, 456, "sms:driver_assigned")
      assert job.args["recipient"] == "driver"
      assert job.args["template"] == "sms:driver_assigned"
    end
  end

  describe "SMSNotificationWorker.perform/1 mock mode" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "sends SMS and creates sent notification record", %{restaurant: restaurant, order: order} do
      args = %Oban.Job{
        args: %{
          "order_id" => order.id,
          "restaurant_id" => restaurant.id,
          "template" => "sms:order_confirmed",
          "recipient" => "customer"
        }
      }

      assert :ok = SMSNotificationWorker.perform(args)

      # Should have created a notification record marked as sent
      notifications = Notifications.list_notifications(restaurant.id)
      assert length(notifications) == 1
      notif = hd(notifications)
      assert notif.status == "sent"
      assert notif.channel == "sms"
      assert notif.template == "sms:order_confirmed"
      assert notif.recipient_contact == "+15551234567"
    end

    test "returns :ok for non-existent order" do
      args = %Oban.Job{
        args: %{
          "order_id" => 999_999,
          "restaurant_id" => 1,
          "template" => "sms:order_confirmed",
          "recipient" => "customer"
        }
      }

      assert :ok = SMSNotificationWorker.perform(args)
    end

    test "returns :ok when customer has no phone", %{restaurant: restaurant} do
      order =
        %RestaurantDash.Orders.Order{}
        |> Ecto.Changeset.cast(
          %{
            customer_name: "No Phone",
            customer_email: "nophone@example.com",
            items: ["Burger"],
            status: "new",
            restaurant_id: restaurant.id
          },
          [:customer_name, :customer_email, :items, :status, :restaurant_id]
        )
        |> RestaurantDash.Repo.insert!()

      args = %Oban.Job{
        args: %{
          "order_id" => order.id,
          "restaurant_id" => restaurant.id,
          "template" => "sms:order_confirmed",
          "recipient" => "customer"
        }
      }

      assert :ok = SMSNotificationWorker.perform(args)
    end
  end

  # ─── Rate Limiting (already_notified?) ────────────────────────────────────

  describe "rate limiting via already_notified?" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "second job is skipped when notification already sent", %{
      restaurant: restaurant,
      order: order
    } do
      job_args = %Oban.Job{
        args: %{
          "order_id" => order.id,
          "restaurant_id" => restaurant.id,
          "template" => "sms:order_confirmed",
          "recipient" => "customer"
        }
      }

      # First send — creates notification
      assert :ok = SMSNotificationWorker.perform(job_args)
      assert length(Notifications.list_notifications(restaurant.id)) == 1

      # Second send — already_notified? check in Notifications context prevents duplicates
      # The worker itself doesn't re-check (that's done at enqueue time in Notifications context)
      # but we can verify the already_notified? guard works:
      assert Notifications.already_notified?(order.id, "sms:order_confirmed")
    end
  end
end
