defmodule RestaurantDash.Menu do
  @moduledoc """
  The Menu context.

  Manages menu categories, items, modifier groups, and modifiers.
  All operations are scoped by restaurant_id to maintain multi-tenancy.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Menu.{Category, Item}

  # ─── Categories ─────────────────────────────────────────────────────────────

  @doc """
  Returns all categories for a restaurant, ordered by position.
  """
  def list_categories(restaurant_id) do
    Category
    |> where([c], c.restaurant_id == ^restaurant_id)
    |> order_by([c], asc: c.position, asc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns active categories for a restaurant, ordered by position.
  """
  def list_active_categories(restaurant_id) do
    Category
    |> where([c], c.restaurant_id == ^restaurant_id and c.is_active == true)
    |> order_by([c], asc: c.position, asc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single category, scoped to a restaurant.
  Returns nil if not found or if it belongs to a different restaurant.
  """
  def get_category(restaurant_id, category_id) do
    Category
    |> where([c], c.restaurant_id == ^restaurant_id and c.id == ^category_id)
    |> Repo.one()
  end

  @doc """
  Gets a single category or raises if not found.
  """
  def get_category!(restaurant_id, category_id) do
    get_category(restaurant_id, category_id) ||
      raise Ecto.NoResultsError, queryable: Category
  end

  @doc """
  Creates a menu category.
  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a menu category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a menu category.
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  @doc """
  Reorders categories for a restaurant.
  Takes a list of category IDs in the desired order.
  """
  def reorder_categories(restaurant_id, category_ids) when is_list(category_ids) do
    category_ids
    |> Enum.with_index(10)
    |> Enum.each(fn {id, position} ->
      Category
      |> where([c], c.id == ^id and c.restaurant_id == ^restaurant_id)
      |> Repo.update_all(set: [position: position * 10])
    end)

    :ok
  end

  # ─── Items ───────────────────────────────────────────────────────────────────

  @doc """
  Returns all items for a restaurant, ordered by position.
  """
  def list_items(restaurant_id) do
    Item
    |> where([i], i.restaurant_id == ^restaurant_id)
    |> order_by([i], asc: i.position, asc: i.inserted_at)
    |> preload(:category)
    |> Repo.all()
  end

  @doc """
  Returns items for a specific category, ordered by position.
  """
  def list_items_by_category(restaurant_id, category_id) do
    Item
    |> where([i], i.restaurant_id == ^restaurant_id and i.menu_category_id == ^category_id)
    |> order_by([i], asc: i.position, asc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns active, available items for a category (customer-facing).
  """
  def list_available_items_by_category(restaurant_id, category_id) do
    Item
    |> where(
      [i],
      i.restaurant_id == ^restaurant_id and
        i.menu_category_id == ^category_id and
        i.is_active == true
    )
    |> order_by([i], asc: i.position, asc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single item, scoped to a restaurant.
  """
  def get_item(restaurant_id, item_id) do
    Item
    |> where([i], i.restaurant_id == ^restaurant_id and i.id == ^item_id)
    |> preload(:category)
    |> Repo.one()
  end

  @doc """
  Gets a single item or raises if not found.
  """
  def get_item!(restaurant_id, item_id) do
    get_item(restaurant_id, item_id) ||
      raise Ecto.NoResultsError, queryable: Item
  end

  @doc """
  Creates a menu item.
  """
  def create_item(attrs \\ %{}) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a menu item.
  """
  def update_item(%Item{} = item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a menu item.
  """
  def delete_item(%Item{} = item) do
    Repo.delete(item)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking item changes.
  """
  def change_item(%Item{} = item, attrs \\ %{}) do
    Item.changeset(item, attrs)
  end

  @doc """
  Toggles item availability (86 / un-86).
  """
  def toggle_item_availability(%Item{} = item) do
    update_item(item, %{is_available: !item.is_available})
  end

  @doc """
  Returns the full menu for a restaurant: active categories with their items.
  Used for public menu display.
  """
  def get_full_menu(restaurant_id) do
    categories = list_active_categories(restaurant_id)

    items =
      Item
      |> where([i], i.restaurant_id == ^restaurant_id and i.is_active == true)
      |> order_by([i], asc: i.position, asc: i.inserted_at)
      |> Repo.all()

    # Group items by category, preserving category order
    items_by_category = Enum.group_by(items, & &1.menu_category_id)

    Enum.map(categories, fn cat ->
      {cat, Map.get(items_by_category, cat.id, [])}
    end)
  end
end
