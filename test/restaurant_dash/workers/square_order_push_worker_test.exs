defmodule RestaurantDash.Workers.SquareOrderPushWorkerTest do
  use RestaurantDash.DataCase, async: true
  use Oban.Testing, repo: RestaurantDash.Repo

  alias RestaurantDash.Workers.SquareOrderPushWorker
  alias RestaurantDash.Integrations.Square
  alias RestaurantDash.{Orders, Tenancy}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Square Push Worker Test",
        slug: "sq-push-worker-test"
      })

    %{restaurant: restaurant}
  end

  describe "perform/1" do
    test "returns :ok when order not found" do
      assert :ok = perform_job(SquareOrderPushWorker, %{"order_id" => 99_999_999})
    end

    test "returns :ok when restaurant has no Square connection", %{restaurant: r} do
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Worker Test",
          items: ["Nachos"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "worker@test.com",
          customer_phone: "555-0300",
          delivery_address: "1 Test Blvd"
        })

      assert :ok = perform_job(SquareOrderPushWorker, %{"order_id" => order.id})
      # Order should NOT have a square_order_id (wasn't connected)
      updated = Orders.get_order(order.id)
      assert is_nil(updated.square_order_id)
    end

    test "pushes order to Square when restaurant is connected", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(
          r,
          "SQ_WPUSH_MERCH",
          "sq_wpush_token",
          "sq_refresh",
          "SQ_WPUSH_LOC"
        )

      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Square Worker Push",
          items: ["Burger"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "wpush@sq.com",
          customer_phone: "555-0301",
          delivery_address: "2 Worker Ave"
        })

      # Reload restaurant for updated Square fields
      restaurant = Tenancy.get_restaurant!(r.id)
      assert Square.connected?(restaurant)

      assert :ok = perform_job(SquareOrderPushWorker, %{"order_id" => order.id})

      # Verify square_order_id was saved
      updated = Orders.get_order(order.id)
      assert is_binary(updated.square_order_id)
      assert String.starts_with?(updated.square_order_id, "MOCK_SQ_ORDER_")
    end

    test "skips order already pushed (has square_order_id)", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_SKIP_MERCH", "sq_skip_token", "sq_refresh")

      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Already Pushed",
          items: ["Pizza"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "skip@sq.com",
          customer_phone: "555-0302",
          delivery_address: "3 Skip Lane"
        })

      # Manually set square_order_id
      order
      |> Ecto.Changeset.change(%{square_order_id: "EXISTING_SQ_ORDER_001"})
      |> RestaurantDash.Repo.update!()

      assert :ok = perform_job(SquareOrderPushWorker, %{"order_id" => order.id})

      # square_order_id should remain unchanged
      updated = Orders.get_order(order.id)
      assert updated.square_order_id == "EXISTING_SQ_ORDER_001"
    end
  end

  describe "enqueue/1" do
    test "enqueues a job in the :square queue", %{restaurant: r} do
      {:ok, order} =
        Orders.create_order(%{
          customer_name: "Enqueue Test",
          items: ["Soda"],
          status: "new",
          restaurant_id: r.id,
          customer_email: "enqueue@sq.com",
          customer_phone: "555-0303",
          delivery_address: "4 Enqueue Rd"
        })

      assert {:ok, job} = SquareOrderPushWorker.enqueue(order.id)
      assert job.queue == "square"
      assert job.args["order_id"] == order.id
    end
  end
end
