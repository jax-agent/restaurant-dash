defmodule RestaurantDash.Workers.SquareInventorySyncWorkerTest do
  use RestaurantDash.DataCase, async: true
  use Oban.Testing, repo: RestaurantDash.Repo

  alias RestaurantDash.Workers.SquareInventorySyncWorker
  alias RestaurantDash.Integrations.Square
  alias RestaurantDash.{Menu, Tenancy}

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Square Inventory Worker Test",
        slug: "sq-inv-worker-test"
      })

    %{restaurant: restaurant}
  end

  describe "perform/1 (specific restaurant)" do
    test "returns :ok when restaurant not found" do
      assert :ok = perform_job(SquareInventorySyncWorker, %{"restaurant_id" => 99_999_999})
    end

    test "returns :ok when restaurant has no Square connection", %{restaurant: r} do
      assert :ok = perform_job(SquareInventorySyncWorker, %{"restaurant_id" => r.id})
    end

    test "syncs inventory for connected restaurant", %{restaurant: r} do
      {:ok, r} =
        Square.save_square_credentials(r, "SQ_ISYNC_MERCH", "sq_isync_token", "sq_refresh")

      {:ok, cat} = Menu.create_category(%{name: "Test Cat", restaurant_id: r.id})

      {:ok, _item} =
        Menu.create_item(%{
          name: "Test Item",
          price: 1000,
          is_available: true,
          restaurant_id: r.id,
          menu_category_id: cat.id
        })

      assert :ok = perform_job(SquareInventorySyncWorker, %{"restaurant_id" => r.id})
    end
  end

  describe "perform/1 (global sync)" do
    test "returns :ok when no Square-connected restaurants" do
      assert :ok = perform_job(SquareInventorySyncWorker, %{})
    end

    test "syncs all connected restaurants" do
      {:ok, r1} =
        Tenancy.create_restaurant(%{name: "SQ Global 1", slug: "sq-global-1"})

      {:ok, _r2} =
        Tenancy.create_restaurant(%{name: "SQ Global 2", slug: "sq-global-2"})

      {:ok, _r1} =
        Square.save_square_credentials(r1, "SQ_G1_MERCH", "sq_g1_token", "sq_refresh")

      # r2 not connected — should be skipped

      assert :ok = perform_job(SquareInventorySyncWorker, %{})
    end
  end

  describe "enqueue_for/1" do
    test "enqueues a sync job for a specific restaurant in :square queue", %{restaurant: r} do
      assert {:ok, job} = SquareInventorySyncWorker.enqueue_for(r.id)
      assert job.queue == "square"
      assert job.args["restaurant_id"] == r.id
    end
  end

  describe "enqueue_global/0" do
    test "enqueues a global sync job in :square queue" do
      assert {:ok, job} = SquareInventorySyncWorker.enqueue_global()
      assert job.queue == "square"
      assert job.args == %{}
    end
  end
end
