defmodule RestaurantDash.Notifications.InAppTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Notifications.InApp
  alias RestaurantDash.Workers.InAppNotificationWorker
  alias RestaurantDash.Notifications

  # ─── Fixtures ──────────────────────────────────────────────────────────────

  defp restaurant_fixture do
    {:ok, r} =
      RestaurantDash.Tenancy.create_restaurant(%{
        name: "InApp Kitchen",
        slug: "inapp-kitchen-#{System.unique_integer([:positive])}",
        address: "1 Test",
        city: "SF",
        state: "CA",
        zip: "94000"
      })

    r
  end

  defp order_fixture(restaurant) do
    %RestaurantDash.Orders.Order{}
    |> Ecto.Changeset.cast(
      %{
        customer_name: "InApp User",
        items: ["Burger"],
        status: "new",
        restaurant_id: restaurant.id,
        total_amount: 1500
      },
      [:customer_name, :items, :status, :restaurant_id, :total_amount]
    )
    |> RestaurantDash.Repo.insert!()
  end

  defp notif_attrs(restaurant_id, order_id, overrides \\ %{}) do
    Map.merge(
      %{
        restaurant_id: restaurant_id,
        order_id: order_id,
        recipient_type: "owner",
        recipient_contact: "in_app",
        channel: "in_app",
        template: "in_app:new_order",
        body: "New order received!"
      },
      overrides
    )
  end

  # ─── InApp Context ─────────────────────────────────────────────────────────

  describe "InApp.list_for_restaurant/2" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "returns in_app notifications for a restaurant", %{restaurant: restaurant, order: order} do
      Notifications.create_notification(notif_attrs(restaurant.id, order.id))
      Notifications.create_notification(notif_attrs(restaurant.id, order.id))

      # Also create an SMS notification (should NOT appear)
      Notifications.create_notification(%{
        restaurant_id: restaurant.id,
        recipient_type: "customer",
        recipient_contact: "+15551234567",
        channel: "sms",
        template: "sms:order_confirmed",
        body: "Confirmed"
      })

      notifications = InApp.list_for_restaurant(restaurant.id)
      assert length(notifications) == 2
      assert Enum.all?(notifications, &(&1.channel == "in_app"))
    end

    test "respects limit", %{restaurant: restaurant, order: order} do
      for _ <- 1..5 do
        Notifications.create_notification(notif_attrs(restaurant.id, order.id))
      end

      notifications = InApp.list_for_restaurant(restaurant.id, 3)
      assert length(notifications) == 3
    end
  end

  describe "InApp.unread_count/1" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "counts pending in-app notifications", %{restaurant: restaurant, order: order} do
      Notifications.create_notification(notif_attrs(restaurant.id, order.id))
      Notifications.create_notification(notif_attrs(restaurant.id, order.id))

      assert InApp.unread_count(restaurant.id) == 2
    end

    test "does not count sent notifications", %{restaurant: restaurant, order: order} do
      {:ok, notif} = Notifications.create_notification(notif_attrs(restaurant.id, order.id))
      Notifications.mark_sent(notif)

      assert InApp.unread_count(restaurant.id) == 0
    end
  end

  describe "InApp.mark_all_read/1" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "marks all pending as sent", %{restaurant: restaurant, order: order} do
      for _ <- 1..3 do
        Notifications.create_notification(notif_attrs(restaurant.id, order.id))
      end

      assert InApp.unread_count(restaurant.id) == 3
      InApp.mark_all_read(restaurant.id)
      assert InApp.unread_count(restaurant.id) == 0
    end
  end

  describe "InApp.mark_read/1" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "marks a single notification as sent", %{restaurant: restaurant, order: order} do
      {:ok, notif} = Notifications.create_notification(notif_attrs(restaurant.id, order.id))

      assert :ok == InApp.mark_read(notif.id) |> elem(0)
      updated = RestaurantDash.Repo.get!(Notifications.Notification, notif.id)
      assert updated.status == "sent"
    end

    test "returns error for unknown id" do
      assert {:error, :not_found} = InApp.mark_read(999_999)
    end
  end

  describe "InApp.create_and_broadcast/2" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "creates notification and returns it", %{restaurant: restaurant, order: order} do
      attrs = notif_attrs(restaurant.id, order.id)

      assert {:ok, notif} = InApp.create_and_broadcast(attrs, [])
      assert notif.channel == "in_app"
    end

    test "broadcasts to subscribed users", %{restaurant: restaurant, order: order} do
      user_id = 999_888

      # Subscribe to the PubSub topic
      InApp.subscribe(user_id)

      attrs = notif_attrs(restaurant.id, order.id)
      InApp.create_and_broadcast(attrs, [user_id])

      assert_receive {:new_notification, notif}
      assert notif.channel == "in_app"
    end
  end

  # ─── InAppNotificationWorker ───────────────────────────────────────────────

  describe "InAppNotificationWorker.perform/1" do
    setup do
      restaurant = restaurant_fixture()
      order = order_fixture(restaurant)
      {:ok, restaurant: restaurant, order: order}
    end

    test "creates in-app notification for new order", %{restaurant: restaurant, order: order} do
      job = %Oban.Job{
        args: %{
          "order_id" => order.id,
          "restaurant_id" => restaurant.id,
          "template" => "in_app:new_order"
        }
      }

      assert :ok = InAppNotificationWorker.perform(job)

      notifications = InApp.list_for_restaurant(restaurant.id)
      assert length(notifications) == 1
      assert hd(notifications).template == "in_app:new_order"
    end

    test "returns :ok for missing order" do
      job = %Oban.Job{
        args: %{
          "order_id" => 999_999,
          "restaurant_id" => 1,
          "template" => "in_app:new_order"
        }
      }

      assert :ok = InAppNotificationWorker.perform(job)
    end

    test "enqueue_for_restaurant/3 inserts Oban job" do
      assert {:ok, job} = InAppNotificationWorker.enqueue_for_restaurant(1, 2, "in_app:new_order")
      assert job.args["template"] == "in_app:new_order"
    end
  end
end
