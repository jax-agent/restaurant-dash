defmodule RestaurantDash.Menu do
  @moduledoc """
  The Menu context.

  Manages menu categories, items, modifier groups, and modifiers.
  All operations are scoped by restaurant_id to maintain multi-tenancy.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Menu.{Category, Item, Modifier, ModifierGroup}

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
  Associates a list of modifier group IDs with a menu item.
  Replaces any existing associations.
  """
  def set_item_modifier_groups(%Item{} = item, modifier_group_ids)
      when is_list(modifier_group_ids) do
    groups =
      ModifierGroup
      |> where([mg], mg.id in ^modifier_group_ids)
      |> Repo.all()

    item
    |> Repo.preload(:modifier_groups)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:modifier_groups, groups)
    |> Repo.update()
  end

  # ─── Modifier Groups ─────────────────────────────────────────────────────────

  @doc """
  Returns all modifier groups for a restaurant.
  """
  def list_modifier_groups(restaurant_id) do
    ModifierGroup
    |> where([g], g.restaurant_id == ^restaurant_id)
    |> order_by([g], asc: g.inserted_at)
    |> preload(:modifiers)
    |> Repo.all()
  end

  @doc """
  Gets a single modifier group scoped to a restaurant.
  """
  def get_modifier_group(restaurant_id, group_id) do
    ModifierGroup
    |> where([g], g.restaurant_id == ^restaurant_id and g.id == ^group_id)
    |> preload(:modifiers)
    |> Repo.one()
  end

  @doc """
  Gets a single modifier group or raises if not found.
  """
  def get_modifier_group!(restaurant_id, group_id) do
    get_modifier_group(restaurant_id, group_id) ||
      raise Ecto.NoResultsError, queryable: ModifierGroup
  end

  @doc """
  Creates a modifier group.
  """
  def create_modifier_group(attrs \\ %{}) do
    %ModifierGroup{}
    |> ModifierGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a modifier group.
  """
  def update_modifier_group(%ModifierGroup{} = group, attrs) do
    group
    |> ModifierGroup.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a modifier group.
  """
  def delete_modifier_group(%ModifierGroup{} = group) do
    Repo.delete(group)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking modifier group changes.
  """
  def change_modifier_group(%ModifierGroup{} = group, attrs \\ %{}) do
    ModifierGroup.changeset(group, attrs)
  end

  # ─── Modifiers ───────────────────────────────────────────────────────────────

  @doc """
  Returns all active modifiers for a modifier group.
  """
  def list_modifiers(group_id) do
    Modifier
    |> where([m], m.modifier_group_id == ^group_id)
    |> order_by([m], asc: m.position, asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single modifier.
  """
  def get_modifier(modifier_id) do
    Repo.get(Modifier, modifier_id)
  end

  @doc """
  Creates a modifier.
  """
  def create_modifier(attrs \\ %{}) do
    %Modifier{}
    |> Modifier.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a modifier.
  """
  def update_modifier(%Modifier{} = modifier, attrs) do
    modifier
    |> Modifier.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a modifier.
  """
  def delete_modifier(%Modifier{} = modifier) do
    Repo.delete(modifier)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking modifier changes.
  """
  def change_modifier(%Modifier{} = modifier, attrs \\ %{}) do
    Modifier.changeset(modifier, attrs)
  end

  # ─── Item–ModifierGroup associations ─────────────────────────────────────────

  @doc """
  Associates a modifier group with a menu item.
  """
  def add_modifier_group_to_item(%Item{} = item, %ModifierGroup{} = group) do
    item = Repo.preload(item, :modifier_groups)

    item
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:modifier_groups, [group | item.modifier_groups])
    |> Repo.update()
  end

  @doc """
  Removes a modifier group from a menu item.
  """
  def remove_modifier_group_from_item(%Item{} = item, %ModifierGroup{} = group) do
    item = Repo.preload(item, :modifier_groups)
    new_groups = Enum.reject(item.modifier_groups, &(&1.id == group.id))

    item
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:modifier_groups, new_groups)
    |> Repo.update()
  end

  @doc """
  Returns a menu item with its modifier groups and modifiers preloaded.
  """
  def get_item_with_modifiers(restaurant_id, item_id) do
    Item
    |> where([i], i.restaurant_id == ^restaurant_id and i.id == ^item_id)
    |> preload(modifier_groups: :modifiers)
    |> Repo.one()
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
      |> preload(modifier_groups: :modifiers)
      |> Repo.all()

    # Group items by category, preserving category order
    items_by_category = Enum.group_by(items, & &1.menu_category_id)

    Enum.map(categories, fn cat ->
      {cat, Map.get(items_by_category, cat.id, [])}
    end)
  end
end
