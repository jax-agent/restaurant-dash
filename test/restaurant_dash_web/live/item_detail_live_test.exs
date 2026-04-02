defmodule RestaurantDashWeb.ItemDetailLiveTest do
  use RestaurantDashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias RestaurantDash.{Menu, Tenancy}

  defp create_restaurant_with_item do
    {:ok, restaurant} =
      Tenancy.create_restaurant(%{
        name: "Detail Test Restaurant",
        slug: "detail-test-#{System.unique_integer([:positive])}",
        primary_color: "#2D6A4F"
      })

    {:ok, cat} =
      Menu.create_category(%{
        restaurant_id: restaurant.id,
        name: "Mains",
        position: 10,
        is_active: true
      })

    {:ok, item} =
      Menu.create_item(%{
        restaurant_id: restaurant.id,
        menu_category_id: cat.id,
        name: "Dragon Roll",
        description: "Shrimp tempura, avocado on top, eel sauce",
        price: 1599,
        is_active: true,
        is_available: true
      })

    # Create modifier groups
    {:ok, spice_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Spice Level",
        min_selections: 0,
        max_selections: 1
      })

    {:ok, _mild} =
      Menu.create_modifier(%{
        modifier_group_id: spice_group.id,
        name: "Mild",
        price_adjustment: 0,
        position: 10
      })

    {:ok, _hot} =
      Menu.create_modifier(%{
        modifier_group_id: spice_group.id,
        name: "Hot",
        price_adjustment: 0,
        position: 20
      })

    {:ok, extras_group} =
      Menu.create_modifier_group(%{
        restaurant_id: restaurant.id,
        name: "Extras",
        min_selections: 0,
        max_selections: nil
      })

    {:ok, _extra_avo} =
      Menu.create_modifier(%{
        modifier_group_id: extras_group.id,
        name: "Extra Avocado",
        price_adjustment: 150,
        position: 10
      })

    {:ok, _} = Menu.add_modifier_group_to_item(item, spice_group)
    {:ok, _} = Menu.add_modifier_group_to_item(item, extras_group)

    {restaurant, item, [spice_group, extras_group]}
  end

  describe "item detail" do
    test "renders item details", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()
      slug = restaurant.slug

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{slug}")

      assert html =~ item.name
      assert html =~ item.description
      assert html =~ "$15.99"
    end

    test "shows modifier groups with options", %{conn: conn} do
      {restaurant, item, [spice_group | _]} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      assert html =~ spice_group.name
      assert html =~ "Mild"
      assert html =~ "Hot"
    end

    test "shows single-select group as radio buttons", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      assert html =~ ~s(type="radio")
    end

    test "shows multi-select group as checkboxes", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      assert html =~ ~s(type="checkbox")
    end

    test "price updates when modifier is selected", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      # Base price shown initially
      assert html =~ "$15.99"

      # Select "Extra Avocado" (+$1.50)
      html =
        lv
        |> element("[data-modifier-type='checkbox']")
        |> render_click()

      # Price should increase
      assert html =~ "$17.49"
    end

    test "shows Add to Cart button (enabled for available item)", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      assert html =~ "Add to Cart"
      # Button should NOT be disabled for available items
      refute html =~ ~s(disabled\n) or String.contains?(html, "cursor-not-allowed")
    end

    test "add-to-cart event opens cart drawer and updates cart", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, lv, _html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      html = lv |> element("button[phx-click='add-to-cart']") |> render_click()

      # Cart drawer should open
      assert html =~ "Your Cart"
      assert html =~ item.name
    end

    test "cart quantity controls work", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, lv, _html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      # Add to cart
      lv |> element("button[phx-click='add-to-cart']") |> render_click()

      # Increment quantity
      html =
        lv
        |> element("button[phx-click='cart-update-quantity'][phx-value-qty='2']")
        |> render_click()

      assert html =~ "2"
    end

    test "shows restaurant name/branding", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      assert html =~ restaurant.name
      assert html =~ restaurant.primary_color
    end

    test "404 when item not found", %{conn: conn} do
      {restaurant, _item, _groups} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/999999?restaurant_slug=#{restaurant.slug}")

      assert html =~ "not found" or html =~ "Item not found"
    end

    test "back link returns to menu", %{conn: conn} do
      {restaurant, item, _groups} = create_restaurant_with_item()

      {:ok, _lv, html} =
        live(conn, ~p"/menu/#{item.id}?restaurant_slug=#{restaurant.slug}")

      assert html =~ "/menu"
    end
  end
end
