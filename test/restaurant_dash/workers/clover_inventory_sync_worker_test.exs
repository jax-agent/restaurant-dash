defmodule RestaurantDash.Workers.CloverInventorySyncWorkerTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Workers.CloverInventorySyncWorker
  alias RestaurantDash.{Tenancy, Menu}
  alias RestaurantDash.Integrations.Clover

  setup do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Sync Test Restaurant",
        slug: "sync-test-#{System.unique_integer([:positive])}"
      })

    %{restaurant: restaurant}
  end

  describe "perform/1 with restaurant_id" do
    test "returns :ok for unconnected restaurant (graceful skip)", %{restaurant: restaurant} do
      job = %Oban.Job{args: %{"restaurant_id" => restaurant.id}}
      # Unconnected → no error raised, just logs and returns :ok
      assert :ok = CloverInventorySyncWorker.perform(job)
    end

    test "returns :ok for connected restaurant", %{restaurant: restaurant} do
      {:ok, _r} = Clover.save_clover_credentials(restaurant, "MERCH_SYNC_W", "tok_sync")
      job = %Oban.Job{args: %{"restaurant_id" => restaurant.id}}
      assert :ok = CloverInventorySyncWorker.perform(job)
    end

    test "returns :ok for non-existent restaurant_id" do
      job = %Oban.Job{args: %{"restaurant_id" => 99_999_999}}
      assert :ok = CloverInventorySyncWorker.perform(job)
    end
  end

  describe "perform/1 global (no restaurant_id)" do
    test "processes all connected restaurants", %{restaurant: restaurant} do
      {:ok, _r} = Clover.save_clover_credentials(restaurant, "MERCH_GLOBAL", "tok_global")
      job = %Oban.Job{args: %{}}
      assert :ok = CloverInventorySyncWorker.perform(job)
    end

    test "returns :ok when no restaurants connected" do
      # No restaurants have Clover in this test's scope
      job = %Oban.Job{args: %{}}
      assert :ok = CloverInventorySyncWorker.perform(job)
    end
  end

  describe "enqueue_for/1" do
    test "enqueues a sync job for a specific restaurant", %{restaurant: restaurant} do
      assert {:ok, _job} = CloverInventorySyncWorker.enqueue_for(restaurant.id)
    end
  end

  describe "enqueue_global/0" do
    test "enqueues a global sync job" do
      assert {:ok, _job} = CloverInventorySyncWorker.enqueue_global()
    end
  end

  describe "inventory sync availability updates" do
    test "marks pizza as unavailable when syncing", %{restaurant: restaurant} do
      {:ok, restaurant} =
        Clover.save_clover_credentials(restaurant, "MERCH_AVAIL", "tok_avail")

      {:ok, cat} =
        Menu.create_category(%{
          name: "Italian",
          restaurant_id: restaurant.id
        })

      {:ok, pizza} =
        Menu.create_item(%{
          name: "Margherita Pizza",
          price: 1599,
          is_available: true,
          restaurant_id: restaurant.id,
          menu_category_id: cat.id
        })

      assert pizza.is_available == true

      job = %Oban.Job{args: %{"restaurant_id" => restaurant.id}}
      assert :ok = CloverInventorySyncWorker.perform(job)

      # Pizza should now be unavailable (mock stock = 0)
      updated = RestaurantDash.Repo.get!(RestaurantDash.Menu.Item, pizza.id)
      assert updated.is_available == false
    end
  end
end
