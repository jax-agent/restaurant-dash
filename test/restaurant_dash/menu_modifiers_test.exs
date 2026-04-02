defmodule RestaurantDash.MenuModifiersTest do
  use RestaurantDash.DataCase, async: true

  alias RestaurantDash.Menu
  alias RestaurantDash.Menu.{Modifier, ModifierGroup}
  alias RestaurantDash.Tenancy

  # ─── Fixtures ────────────────────────────────────────────────────────────────

  defp create_restaurant do
    {:ok, r} =
      Tenancy.create_restaurant(%{
        name: "Test Restaurant",
        slug: "test-modifier-#{System.unique_integer([:positive])}",
        primary_color: "#E63946"
      })

    r
  end

  defp create_category(restaurant_id) do
    {:ok, cat} = Menu.create_category(%{name: "Test Cat", restaurant_id: restaurant_id})
    cat
  end

  defp create_item(restaurant_id, category_id) do
    {:ok, item} =
      Menu.create_item(%{
        name: "Test Item",
        price: 1000,
        restaurant_id: restaurant_id,
        menu_category_id: category_id
      })

    item
  end

  defp create_group(restaurant_id, attrs \\ %{}) do
    {:ok, group} =
      Menu.create_modifier_group(
        Map.merge(%{name: "Test Group", restaurant_id: restaurant_id}, attrs)
      )

    group
  end

  defp create_modifier(group_id, attrs \\ %{}) do
    {:ok, mod} =
      Menu.create_modifier(Map.merge(%{name: "Option A", modifier_group_id: group_id}, attrs))

    mod
  end

  # ─── ModifierGroup CRUD ───────────────────────────────────────────────────────

  describe "list_modifier_groups/1" do
    test "returns all modifier groups for a restaurant" do
      r = create_restaurant()
      g = create_group(r.id, %{name: "Size"})
      groups = Menu.list_modifier_groups(r.id)
      assert Enum.any?(groups, &(&1.id == g.id))
    end

    test "does not return groups from another restaurant" do
      r1 = create_restaurant()
      r2 = create_restaurant()
      _g1 = create_group(r1.id)
      g2 = create_group(r2.id)
      groups = Menu.list_modifier_groups(r1.id)
      refute Enum.any?(groups, &(&1.id == g2.id))
    end
  end

  describe "create_modifier_group/1" do
    test "creates a group with valid attrs" do
      r = create_restaurant()

      assert {:ok, %ModifierGroup{} = group} =
               Menu.create_modifier_group(%{
                 name: "Size",
                 min_selections: 1,
                 max_selections: 1,
                 restaurant_id: r.id
               })

      assert group.name == "Size"
      assert group.min_selections == 1
      assert group.max_selections == 1
    end

    test "creates an optional group (min_selections 0)" do
      r = create_restaurant()
      assert {:ok, group} = Menu.create_modifier_group(%{name: "Extras", restaurant_id: r.id})
      assert group.min_selections == 0
    end

    test "creates an unlimited multi-select group (max_selections nil)" do
      r = create_restaurant()

      assert {:ok, group} =
               Menu.create_modifier_group(%{
                 name: "Toppings",
                 min_selections: 0,
                 max_selections: nil,
                 restaurant_id: r.id
               })

      assert group.max_selections == nil
    end

    test "fails when max_selections < min_selections" do
      r = create_restaurant()

      assert {:error, changeset} =
               Menu.create_modifier_group(%{
                 name: "Bad Group",
                 min_selections: 3,
                 max_selections: 1,
                 restaurant_id: r.id
               })

      assert %{max_selections: _} = errors_on(changeset)
    end

    test "fails without required fields" do
      assert {:error, changeset} = Menu.create_modifier_group(%{})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :restaurant_id)
    end
  end

  describe "update_modifier_group/2" do
    test "updates a modifier group" do
      r = create_restaurant()
      group = create_group(r.id)
      assert {:ok, updated} = Menu.update_modifier_group(group, %{name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "delete_modifier_group/1" do
    test "deletes a modifier group" do
      r = create_restaurant()
      group = create_group(r.id)
      assert {:ok, _} = Menu.delete_modifier_group(group)
      assert Menu.get_modifier_group(r.id, group.id) == nil
    end
  end

  # ─── Modifier CRUD ────────────────────────────────────────────────────────────

  describe "create_modifier/1" do
    test "creates a modifier with valid attrs" do
      r = create_restaurant()
      group = create_group(r.id)

      assert {:ok, %Modifier{} = mod} =
               Menu.create_modifier(%{
                 name: "Large",
                 price_adjustment: 300,
                 position: 10,
                 modifier_group_id: group.id
               })

      assert mod.name == "Large"
      assert mod.price_adjustment == 300
      assert mod.is_active == true
    end

    test "allows zero price_adjustment (no upcharge)" do
      r = create_restaurant()
      group = create_group(r.id)

      assert {:ok, mod} =
               Menu.create_modifier(%{
                 name: "Regular",
                 price_adjustment: 0,
                 modifier_group_id: group.id
               })

      assert mod.price_adjustment == 0
    end

    test "fails without required fields" do
      assert {:error, changeset} = Menu.create_modifier(%{})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :modifier_group_id)
    end
  end

  describe "list_modifiers/1" do
    test "returns modifiers for a group in order" do
      r = create_restaurant()
      group = create_group(r.id)
      _m1 = create_modifier(group.id, %{name: "Large", position: 30})
      _m2 = create_modifier(group.id, %{name: "Small", position: 10})
      _m3 = create_modifier(group.id, %{name: "Medium", position: 20})

      [first, second, third] = Menu.list_modifiers(group.id)
      assert first.name == "Small"
      assert second.name == "Medium"
      assert third.name == "Large"
    end
  end

  describe "update_modifier/2" do
    test "updates a modifier" do
      r = create_restaurant()
      group = create_group(r.id)
      mod = create_modifier(group.id)

      assert {:ok, updated} =
               Menu.update_modifier(mod, %{name: "Extra Large", price_adjustment: 500})

      assert updated.name == "Extra Large"
      assert updated.price_adjustment == 500
    end
  end

  describe "delete_modifier/1" do
    test "deletes a modifier" do
      r = create_restaurant()
      group = create_group(r.id)
      mod = create_modifier(group.id)
      assert {:ok, _} = Menu.delete_modifier(mod)
      assert Menu.get_modifier(mod.id) == nil
    end
  end

  # ─── Item–ModifierGroup associations ─────────────────────────────────────────

  describe "add_modifier_group_to_item/2 and remove_modifier_group_from_item/2" do
    test "adds a modifier group to an item" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id)
      group = create_group(r.id, %{name: "Size"})

      assert {:ok, _} = Menu.add_modifier_group_to_item(item, group)

      loaded = Menu.get_item_with_modifiers(r.id, item.id)
      assert Enum.any?(loaded.modifier_groups, &(&1.id == group.id))
    end

    test "removes a modifier group from an item" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id)
      group = create_group(r.id, %{name: "Size"})
      {:ok, _} = Menu.add_modifier_group_to_item(item, group)

      item_with_group = Menu.get_item_with_modifiers(r.id, item.id)
      assert {:ok, _} = Menu.remove_modifier_group_from_item(item_with_group, group)

      loaded = Menu.get_item_with_modifiers(r.id, item.id)
      refute Enum.any?(loaded.modifier_groups, &(&1.id == group.id))
    end
  end

  describe "get_item_with_modifiers/2" do
    test "returns item with modifier groups and modifiers preloaded" do
      r = create_restaurant()
      cat = create_category(r.id)
      item = create_item(r.id, cat.id)
      group = create_group(r.id, %{name: "Spice Level"})
      _mod_mild = create_modifier(group.id, %{name: "Mild"})
      _mod_hot = create_modifier(group.id, %{name: "Hot"})
      {:ok, _} = Menu.add_modifier_group_to_item(item, group)

      loaded = Menu.get_item_with_modifiers(r.id, item.id)
      assert length(loaded.modifier_groups) == 1
      [loaded_group] = loaded.modifier_groups
      assert loaded_group.name == "Spice Level"
      assert length(loaded_group.modifiers) == 2
    end
  end

  # ─── ModifierGroup helpers ────────────────────────────────────────────────────

  describe "ModifierGroup.multi_select?/1" do
    test "returns true when max_selections is nil" do
      group = %ModifierGroup{max_selections: nil}
      assert ModifierGroup.multi_select?(group) == true
    end

    test "returns true when max_selections > 1" do
      group = %ModifierGroup{max_selections: 3}
      assert ModifierGroup.multi_select?(group) == true
    end

    test "returns false when max_selections == 1" do
      group = %ModifierGroup{max_selections: 1}
      assert ModifierGroup.multi_select?(group) == false
    end
  end

  describe "ModifierGroup.optional?/1" do
    test "returns true when min_selections == 0" do
      assert ModifierGroup.optional?(%ModifierGroup{min_selections: 0}) == true
    end

    test "returns false when min_selections > 0" do
      assert ModifierGroup.optional?(%ModifierGroup{min_selections: 1}) == false
    end
  end

  # ─── Modifier.format_price_adjustment/1 ──────────────────────────────────────

  describe "Modifier.format_price_adjustment/1" do
    test "returns 'Free' for 0" do
      assert Modifier.format_price_adjustment(0) == "Free"
    end

    test "formats positive adjustment" do
      assert Modifier.format_price_adjustment(150) == "+$1.50"
      assert Modifier.format_price_adjustment(300) == "+$3.00"
    end

    test "formats negative adjustment" do
      assert Modifier.format_price_adjustment(-100) == "-$1.00"
    end
  end
end
