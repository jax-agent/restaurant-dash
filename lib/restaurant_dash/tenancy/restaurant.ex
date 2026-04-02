defmodule RestaurantDash.Tenancy.Restaurant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "restaurants" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :phone, :string
    field :address, :string
    field :city, :string
    field :state, :string
    field :zip, :string
    field :primary_color, :string, default: "#E63946"
    field :logo_url, :string
    field :timezone, :string, default: "America/Chicago"
    field :is_active, :boolean, default: true
    field :stripe_account_id, :string
    field :auto_dispatch_enabled, :boolean, default: false
    field :lat, :float
    field :lng, :float

    has_many :orders, RestaurantDash.Orders.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(restaurant, attrs) do
    restaurant
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :phone,
      :address,
      :city,
      :state,
      :zip,
      :primary_color,
      :logo_url,
      :timezone,
      :is_active
    ])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:slug, min: 2, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase letters, numbers, and hyphens only"
    )
    |> unique_constraint(:slug)
    |> validate_format(:primary_color, ~r/^#[0-9A-Fa-f]{6}$/,
      message: "must be a valid hex color like #RRGGBB"
    )
  end

  @doc """
  Generates a slug from a restaurant name.
  """
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  def slugify(_), do: ""
end
