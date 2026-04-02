defmodule RestaurantDash.MenuTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Menu
  alias RestaurantDash.Menu.{Category, Item}
  alias RestaurantDash.Tenancy

  # ─── Fixtures ────────────────────────────────────────────────────────────────

  defp create_restaurant(attrs \\ %{}) do
    {:ok, restaurant} =
      Tenancy.create_restaurant(
        Map.merge(
          %{
            name: "Test Restaurant",
            slug: "test-restaurant-#{System.unique_integer([:positive])}",
            primary_color: "#E63946"
          },
          attrs
        )
      )

    restaurant
  end

  defp create_category(restaurant_id, attrs \\ %{}) do
    {:ok, category} =
      Menu.create_category(
        Map.merge(%{name: "Test Category", restaurant_id: restaurant_id}, attrs)
      )

    category
  end

  defp create_item(restaurant_id, category_id, attrs \\ %{}) do
    {:ok, item} =
      Menu.create_item(
        Map.merge(
          %{
            name: "Test Item",
            price: 1000,
            restaurant_id: restaurant_id,
            menu_category_id: category_id
          },
          attrs
        )
      )

    item
  end

  # ─── Category CRUD ───────────────────────────────────────────────────────────

  describe "list_categories/1" do
    test "returns all categories for a restaurant" do
      r = create_restaurant()
      cat = create_category(r.id, %{name: "Appetizers"})
      categories = Menu.list_categories(r.id)
      assert Enum.any?(categories, &(&1.id == cat.id))
    end

    test "does not return categories from other restaurants" do
      r1 = create_restaurant()
      r2 = create_restaurant()
      _cat1 = create_category(r1.id, %{name: "Pizzas"})
      cat2 = create_category(r2.id, %{name: "Sushi"})
      categories = Menu.list_categories(r1.id)
      refute Enum.any?(categories, &(&1.id == cat2.id))
    end

    test "returns categories ordered by position" do
      r = create_restaurant()
      _c1 = create_category(r.id, %{name: "Drinks", position: 30})
      _c2 = create_category(r.id, %{name: "Appetizers", position: 10})
      _c3 = create_category(r.id, %{name: "Mains", position: 20})

      [first, second, third] = Menu.list_categories(r.id)
      assert first.name == "Appetizers"
      assert second.name == "Mains"
      assert third.name == "Drinks"
    end
  end

  describe "list_active_categories/1" do
    test "only returns active categories" do
      r = create_restaurant()
      _active = create_category(r.id, %{name: "Active", is_active: true})
      _inactive = create_category(r.id, %{name: "Inactive", is_active: false})
      categories = Menu.list_active_categories(r.id)
      assert Enum.all?(categories, & &1.is_active)
      assert length(categories) == 1
    end
  end

  describe "get_category/2" do
    test "returns the category when it belongs to the restaurant" do
      r = create_restaurant()
      cat = create_category(r.id)
      assert Menu.get_category(r.id, cat.id).id == cat.id
    end

    test "returns nil when category belongs to a different restaurant" do
      r1 = create_restaurant()
      r2 = create_restaurant()
      cat = create_category(r2.id)
      assert Menu.get_category(r1.id, cat.id) == nil
    end

    test "returns nil when category doesn't exist" do
      r = create_restaurant()
      assert Menu.get_category(r.id, -1) == nil
    end
  end

  describe "create_category/1" do
    test "creates a category with valid attrs" do
      r = create_restaurant()

      assert {:ok, %Category{} = cat} =
               Menu.create_category(%{
                 name: "Appetizers",
                 description: "Small plates to start",
                 position: 10,
                 restaurant_id: r.id
               })

      assert cat.name == "Appetizers"
      assert cat.description == "Small plates to start"
      assert cat.position == 10
      assert cat.restaurant_id == r.id
      assert cat.is_active == true
    end

    test "fails without required fields" do
      assert {:error, changeset} = Menu.create_category(%{})
      assert %{name: ["can't be blank"], restaurant_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with invalid restaurant_id" do
      assert {:error, _changeset} = Menu.create_category(%{name: "Test", restaurant_id: -1})
    end
  end

  describe "update_category/2" do
    test "updates a category with valid attrs" do
      r = create_restaurant()
      cat = create_category(r.id)
      assert {:ok, updated} = Menu.update_category(cat, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "fails with invalid attrs" do
      r = create_restaurant()
      cat = create_category(r.id)
      assert {:error, changeset} = Menu.update_category(cat, %{name: ""})
      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "delete_category/1" do
    test "deletes the category" do
      r = create_restaurant()
      cat = create_category(r.id)
      assert {:ok, _} = Menu.delete_category(cat)
      assert Menu.get_category(r.id, cat.id) == nil
    end
  end

  describe "reorder_categories/2" do
    test "reorders categories by assigning new positions" do
      r = create_restaurant()
      c1 = create_category(r.id, %{name: "C1", position: 10})
      c2 = create_category(r.id, %{name: "C2", position: 20})
      c3 = create_category(r.id, %{name: "C3", position: 30})

      # Reorder: c3, c1, c2
      :ok = Menu.reorder_categories(r.id, [c3.id, c1.id, c2.id])

      [first, second, third] = Menu.list_categories(r.id)
      assert first.id == c3.id
      assert second.id == c1.id
      assert third.id == c2.id
    end
  end

  # ─── Item CRUD ───────────────────────────────────────────────────────────────

  describe "list_items/1" do
    test "returns all items for a restaurant" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id, %{name: "Margherita Pizza"})
      items = Menu.list_items(r.id)
      assert Enum.any?(items, &(&1.id == item.id))
    end

    test "does not return items from other restaurants" do
      r1 = create_restaurant()
      r2 = create_restaurant()
      cat1 = create_category(r1.id)
      cat2 = create_category(r2.id)
      _item1 = create_item(r1.id, cat1.id)
      item2 = create_item(r2.id, cat2.id)
      items = Menu.list_items(r1.id)
      refute Enum.any?(items, &(&1.id == item2.id))
    end
  end

  describe "list_items_by_category/2" do
    test "returns items for a specific category" do
      r = create_restaurant()
      cat1 = create_category(r.id, %{name: "Appetizers"})
      cat2 = create_category(r.id, %{name: "Mains"})
      app = create_item(r.id, cat1.id, %{name: "Bruschetta"})
      main = create_item(r.id, cat2.id, %{name: "Pasta"})

      items = Menu.list_items_by_category(r.id, cat1.id)
      assert Enum.any?(items, &(&1.id == app.id))
      refute Enum.any?(items, &(&1.id == main.id))
    end
  end

  describe "create_item/1" do
    test "creates an item with valid attrs" do
      r = create_restaurant()
      cat = create_category(r.id)

      assert {:ok, %Item{} = item} =
               Menu.create_item(%{
                 name: "Margherita Pizza",
                 description: "Classic tomato and cheese",
                 price: 1299,
                 position: 10,
                 restaurant_id: r.id,
                 menu_category_id: cat.id
               })

      assert item.name == "Margherita Pizza"
      assert item.price == 1299
      assert item.is_active == true
      assert item.is_available == true
    end

    test "fails without required fields" do
      assert {:error, changeset} = Menu.create_item(%{})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :restaurant_id)
    end

    test "fails with negative price" do
      r = create_restaurant()
      cat = create_category(r.id)

      assert {:error, changeset} =
               Menu.create_item(%{
                 name: "Item",
                 price: -100,
                 restaurant_id: r.id,
                 menu_category_id: cat.id
               })

      assert %{price: _} = errors_on(changeset)
    end

    test "allows price of zero (free item)" do
      r = create_restaurant()
      cat = create_category(r.id)

      assert {:ok, item} =
               Menu.create_item(%{
                 name: "Free Item",
                 price: 0,
                 restaurant_id: r.id,
                 menu_category_id: cat.id
               })

      assert item.price == 0
    end
  end

  describe "update_item/2" do
    test "updates an item" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id)
      assert {:ok, updated} = Menu.update_item(item, %{name: "Updated Item", price: 1999})
      assert updated.name == "Updated Item"
      assert updated.price == 1999
    end
  end

  describe "delete_item/1" do
    test "deletes an item" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id)
      assert {:ok, _} = Menu.delete_item(item)
      assert Menu.get_item(r.id, item.id) == nil
    end
  end

  describe "toggle_item_availability/1" do
    test "marks an available item as unavailable" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id, %{is_available: true})
      assert {:ok, updated} = Menu.toggle_item_availability(item)
      assert updated.is_available == false
    end

    test "marks an unavailable item as available (un-86)" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id, %{is_available: false})
      assert {:ok, updated} = Menu.toggle_item_availability(item)
      assert updated.is_available == true
    end
  end

  describe "get_full_menu/1" do
    test "returns categories with their items grouped" do
      r = create_restaurant()
      cat1 = create_category(r.id, %{name: "Appetizers", position: 10, is_active: true})
      cat2 = create_category(r.id, %{name: "Mains", position: 20, is_active: true})
      _inactive_cat = create_category(r.id, %{name: "Hidden", is_active: false})

      item1 = create_item(r.id, cat1.id, %{name: "Bruschetta", is_active: true})
      item2 = create_item(r.id, cat2.id, %{name: "Pasta", is_active: true})
      _inactive_item = create_item(r.id, cat1.id, %{name: "Hidden Item", is_active: false})

      menu = Menu.get_full_menu(r.id)

      assert length(menu) == 2

      {first_cat, first_items} = Enum.at(menu, 0)
      assert first_cat.id == cat1.id
      assert Enum.any?(first_items, &(&1.id == item1.id))
      refute Enum.any?(first_items, &(&1.name == "Hidden Item"))

      {second_cat, second_items} = Enum.at(menu, 1)
      assert second_cat.id == cat2.id
      assert Enum.any?(second_items, &(&1.id == item2.id))
    end
  end

  # ─── Item.format_price/1 ─────────────────────────────────────────────────────

  describe "Item.format_price/1" do
    test "formats cents to dollars string" do
      assert Item.format_price(1599) == "$15.99"
      assert Item.format_price(1200) == "$12.00"
      assert Item.format_price(100) == "$1.00"
      assert Item.format_price(0) == "$0.00"
      assert Item.format_price(50) == "$0.50"
    end
  end
end
