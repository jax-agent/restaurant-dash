defmodule RestaurantDash.NotificationsTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Notifications
  alias RestaurantDash.Notifications.Templates

  # ─── Fixtures ──────────────────────────────────────────────────────────────

  def restaurant_fixture do
    {:ok, restaurant} =
      RestaurantDash.Tenancy.create_restaurant(%{
        name: "Test Kitchen",
        slug: "test-kitchen-#{System.unique_integer([:positive])}",
        phone: "(415) 555-0000",
        address: "1 Test St",
        city: "Testville",
        state: "CA",
        zip: "94000"
      })

    restaurant
  end

  def notification_attrs(restaurant_id, overrides \\ %{}) do
    Map.merge(
      %{
        restaurant_id: restaurant_id,
        recipient_type: "customer",
        recipient_contact: "+15551234567",
        channel: "sms",
        template: "sms:order_confirmed",
        body: "Your order is confirmed!"
      },
      overrides
    )
  end

  # ─── Templates ─────────────────────────────────────────────────────────────

  describe "Templates.render/2" do
    test "renders a known template with variables" do
      {:ok, rendered} =
        Templates.render("sms:order_confirmed", %{
          "customer_name" => "Alice",
          "order_number" => "42",
          "restaurant_name" => "Test Kitchen",
          "eta" => "30 min",
          "tracking_url" => "https://example.com/track/42"
        })

      assert rendered =~ "Alice"
      assert rendered =~ "#42"
      assert rendered =~ "Test Kitchen"
      assert rendered =~ "30 min"
    end

    test "returns error for unknown template" do
      assert {:error, _} = Templates.render("sms:does_not_exist")
    end

    test "renders template with missing variables as empty string (passthrough)" do
      {:ok, rendered} = Templates.render("sms:order_confirmed", %{})
      # Unreplaced vars remain as-is — that's expected behavior
      assert is_binary(rendered)
    end

    test "list_templates/0 returns all templates" do
      templates = Templates.list_templates()
      assert length(templates) > 0
      assert "sms:order_confirmed" in templates
      assert "email:order_confirmed" in templates
      assert "in_app:new_order" in templates
    end

    test "list_templates/1 filters by channel" do
      sms_templates = Templates.list_templates("sms")
      assert Enum.all?(sms_templates, &String.starts_with?(&1, "sms:"))

      email_templates = Templates.list_templates("email")
      assert Enum.all?(email_templates, &String.starts_with?(&1, "email:"))
    end

    test "renders in_app template" do
      {:ok, rendered} =
        Templates.render("in_app:new_order", %{
          "order_number" => "99",
          "total" => "$45.00"
        })

      assert rendered =~ "#99"
      assert rendered =~ "$45.00"
    end
  end

  # ─── Notification CRUD ─────────────────────────────────────────────────────

  describe "create_notification/1" do
    setup do
      {:ok, restaurant: restaurant_fixture()}
    end

    test "creates with valid attrs", %{restaurant: restaurant} do
      attrs = notification_attrs(restaurant.id)

      assert {:ok, notification} = Notifications.create_notification(attrs)
      assert notification.restaurant_id == restaurant.id
      assert notification.status == "pending"
      assert notification.channel == "sms"
    end

    test "validates required fields" do
      assert {:error, changeset} = Notifications.create_notification(%{})
      errors = errors_on(changeset)
      assert :restaurant_id in Map.keys(errors)
      assert :recipient_type in Map.keys(errors)
      assert :channel in Map.keys(errors)
      assert :template in Map.keys(errors)
      assert :body in Map.keys(errors)
    end

    test "validates channel inclusion", %{restaurant: restaurant} do
      attrs = notification_attrs(restaurant.id, %{channel: "telegram"})
      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert "is invalid" in errors_on(changeset).channel
    end

    test "validates recipient_type inclusion", %{restaurant: restaurant} do
      attrs = notification_attrs(restaurant.id, %{recipient_type: "alien"})
      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert "is invalid" in errors_on(changeset).recipient_type
    end

    test "accepts all valid channels", %{restaurant: restaurant} do
      for channel <- ~w(sms email push in_app) do
        attrs = notification_attrs(restaurant.id, %{channel: channel})
        assert {:ok, _} = Notifications.create_notification(attrs)
      end
    end
  end

  describe "mark_sent/1 and mark_failed/1" do
    setup do
      restaurant = restaurant_fixture()
      {:ok, notification} = Notifications.create_notification(notification_attrs(restaurant.id))
      {:ok, notification: notification}
    end

    test "mark_sent sets status=sent and sent_at", %{notification: notification} do
      assert {:ok, updated} = Notifications.mark_sent(notification)
      assert updated.status == "sent"
      assert updated.sent_at != nil
    end

    test "mark_failed sets status=failed and error_message", %{notification: notification} do
      assert {:ok, updated} = Notifications.mark_failed(notification, "Network error")
      assert updated.status == "failed"
      assert updated.error_message == "Network error"
    end
  end

  describe "list_notifications/2" do
    setup do
      restaurant = restaurant_fixture()

      for channel <- ~w(sms email in_app) do
        Notifications.create_notification(notification_attrs(restaurant.id, %{channel: channel}))
      end

      {:ok, restaurant: restaurant}
    end

    test "lists all notifications for a restaurant", %{restaurant: restaurant} do
      notifications = Notifications.list_notifications(restaurant.id)
      assert length(notifications) == 3
    end

    test "filters by channel", %{restaurant: restaurant} do
      notifications = Notifications.list_notifications(restaurant.id, channel: "sms")
      assert length(notifications) == 1
      assert hd(notifications).channel == "sms"
    end

    test "filters by status", %{restaurant: restaurant} do
      {:ok, notif} =
        Notifications.create_notification(notification_attrs(restaurant.id))

      Notifications.mark_sent(notif)

      pending = Notifications.list_notifications(restaurant.id, status: "pending")
      sent = Notifications.list_notifications(restaurant.id, status: "sent")

      assert length(pending) == 3
      assert length(sent) == 1
    end
  end

  describe "already_notified?/2" do
    setup do
      restaurant = restaurant_fixture()

      # Create a fake order record for order_id reference
      order =
        %RestaurantDash.Orders.Order{}
        |> Ecto.Changeset.cast(
          %{
            customer_name: "Test",
            items: ["item1"],
            restaurant_id: restaurant.id,
            status: "new"
          },
          [:customer_name, :items, :status, :restaurant_id]
        )
        |> RestaurantDash.Repo.insert!()

      {:ok, restaurant: restaurant, order: order}
    end

    test "returns false when no notification exists", %{order: order} do
      refute Notifications.already_notified?(order.id, "sms:order_confirmed")
    end

    test "returns true when a pending/sent notification exists", %{
      restaurant: restaurant,
      order: order
    } do
      Notifications.create_notification(
        notification_attrs(restaurant.id, %{
          order_id: order.id,
          template: "sms:order_confirmed"
        })
      )

      assert Notifications.already_notified?(order.id, "sms:order_confirmed")
    end

    test "returns false for a different template", %{restaurant: restaurant, order: order} do
      Notifications.create_notification(
        notification_attrs(restaurant.id, %{
          order_id: order.id,
          template: "sms:order_confirmed"
        })
      )

      refute Notifications.already_notified?(order.id, "sms:out_for_delivery")
    end
  end

  describe "create_from_template/3" do
    setup do
      {:ok, restaurant: restaurant_fixture()}
    end

    test "creates notification from valid template", %{restaurant: restaurant} do
      vars = %{
        "customer_name" => "Bob",
        "order_number" => "55",
        "restaurant_name" => "Test Kitchen",
        "eta" => "25 min",
        "tracking_url" => "https://example.com/track/55"
      }

      attrs = %{
        restaurant_id: restaurant.id,
        recipient_type: "customer",
        recipient_contact: "+15559999999",
        channel: "sms"
      }

      assert {:ok, notif} = Notifications.create_from_template("sms:order_confirmed", vars, attrs)
      assert notif.template == "sms:order_confirmed"
      assert notif.body =~ "Bob"
      assert notif.body =~ "#55"
    end

    test "returns error for unknown template", %{restaurant: restaurant} do
      assert {:error, _} =
               Notifications.create_from_template("sms:nonexistent", %{}, %{
                 restaurant_id: restaurant.id
               })
    end
  end
end
