defmodule RestaurantDash.Tenancy do
  @moduledoc """
  The Tenancy context. Manages restaurants (tenants) in the multi-tenant system.
  """

  import Ecto.Query, warn: false
  alias RestaurantDash.Repo
  alias RestaurantDash.Tenancy.Restaurant

  # ─── Queries ───────────────────────────────────────────────────────────────

  @doc "Returns all restaurants."
  def list_restaurants do
    Repo.all(Restaurant)
  end

  @doc "Returns all active restaurants."
  def list_active_restaurants do
    Restaurant
    |> where([r], r.is_active == true)
    |> Repo.all()
  end

  @doc "Gets a restaurant by ID. Raises if not found."
  def get_restaurant!(id), do: Repo.get!(Restaurant, id)

  @doc "Gets a restaurant by ID. Returns nil if not found."
  def get_restaurant(id), do: Repo.get(Restaurant, id)

  @doc "Gets a restaurant by slug. Returns nil if not found."
  def get_restaurant_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Restaurant, slug: slug, is_active: true)
  end

  # ─── Mutations ─────────────────────────────────────────────────────────────

  @doc "Creates a restaurant."
  def create_restaurant(attrs \\ %{}) do
    %Restaurant{}
    |> Restaurant.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a restaurant."
  def update_restaurant(%Restaurant{} = restaurant, attrs) do
    restaurant
    |> Restaurant.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a restaurant."
  def delete_restaurant(%Restaurant{} = restaurant) do
    Repo.delete(restaurant)
  end

  @doc "Returns a changeset for a restaurant."
  def change_restaurant(%Restaurant{} = restaurant, attrs \\ %{}) do
    Restaurant.changeset(restaurant, attrs)
  end

  # ─── User helpers ──────────────────────────────────────────────────────────

  @doc "Returns user IDs for all owners of a restaurant."
  def list_owner_user_ids(restaurant_id) do
    RestaurantDash.Accounts.User
    |> where([u], u.restaurant_id == ^restaurant_id and u.role == "owner")
    |> select([u], u.id)
    |> Repo.all()
  end

  # ─── Slug helpers ──────────────────────────────────────────────────────────

  @doc "Generates a URL-safe slug from a name."
  defdelegate slugify(name), to: Restaurant
end
