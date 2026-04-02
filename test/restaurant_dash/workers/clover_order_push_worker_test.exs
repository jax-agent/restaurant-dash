defmodule RestaurantDash.Workers.CloverOrderPushWorkerTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Workers.CloverOrderPushWorker
  alias RestaurantDash.{Orders, Tenancy}
  alias RestaurantDash.Integrations.Clover

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Clover Push Test Restaurant",
        slug: "clover-push-test-#{System.unique_integer([:positive])}"
      })

    {:ok, order} =
      Orders.create_order(%{
        customer_name: "Push Worker Test",
        items: ["Burger"],
        status: "new",
        restaurant_id: restaurant.id,
        customer_email: "worker@example.com",
        customer_phone: "555-0202",
        delivery_address: "789 Oak Ave"
      })

    %{restaurant: restaurant, order: order}
  end

  describe "perform/1" do
    test "skips gracefully when order not found" do
      job = %Oban.Job{args: %{"order_id" => 99_999_999}}
      assert :ok = CloverOrderPushWorker.perform(job)
    end

    test "skips gracefully when restaurant not connected to Clover", %{order: order} do
      job = %Oban.Job{args: %{"order_id" => order.id}}
      # Restaurant has no Clover credentials → should return :ok (not raise)
      assert :ok = CloverOrderPushWorker.perform(job)
    end

    test "pushes order when restaurant is connected", %{restaurant: restaurant, order: order} do
      {:ok, _restaurant} = Clover.save_clover_credentials(restaurant, "MERCH_WORKER", "tok_123")

      job = %Oban.Job{args: %{"order_id" => order.id}}
      assert :ok = CloverOrderPushWorker.perform(job)

      # Verify clover_order_id was saved
      updated = Orders.get_order(order.id)
      assert is_binary(updated.clover_order_id)
      assert String.starts_with?(updated.clover_order_id, "MOCK_ORDER_")
    end

    test "skips if order already has a clover_order_id", %{restaurant: restaurant, order: order} do
      {:ok, _r} = Clover.save_clover_credentials(restaurant, "MERCH_SKIP", "tok_456")

      # Pre-set clover_order_id
      order
      |> Ecto.Changeset.change(%{clover_order_id: "EXISTING_ORDER_ID"})
      |> RestaurantDash.Repo.update!()

      job = %Oban.Job{args: %{"order_id" => order.id}}
      assert :ok = CloverOrderPushWorker.perform(job)

      # Should still be the same ID
      updated = Orders.get_order(order.id)
      assert updated.clover_order_id == "EXISTING_ORDER_ID"
    end
  end

  describe "enqueue/1" do
    test "enqueues a job successfully", %{order: order} do
      # In test mode Oban uses inline testing mode — just verify it returns ok or a job
      assert {:ok, _job} = CloverOrderPushWorker.enqueue(order.id)
    end
  end
end
