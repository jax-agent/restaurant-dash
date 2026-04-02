defmodule RestaurantDash.Hours.OperatingHour do
  use Ecto.Schema
  import Ecto.Changeset

  # 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  @valid_days 0..6

  schema "operating_hours" do
    field :day_of_week, :integer
    field :open_time, :time
    field :close_time, :time
    field :is_closed, :boolean, default: false

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant

    timestamps(type: :utc_datetime)
  end

  def changeset(hour, attrs) do
    hour
    |> cast(attrs, [:restaurant_id, :day_of_week, :open_time, :close_time, :is_closed])
    |> validate_required([:restaurant_id, :day_of_week, :open_time, :close_time])
    |> validate_inclusion(:day_of_week, Enum.to_list(@valid_days))
    |> validate_times()
    |> unique_constraint(:day_of_week, name: :operating_hours_restaurant_id_day_of_week_index)
  end

  defp validate_times(changeset) do
    open = get_field(changeset, :open_time)
    close = get_field(changeset, :close_time)
    is_closed = get_field(changeset, :is_closed)

    if not is_nil(open) and not is_nil(close) and not is_closed do
      if Time.compare(open, close) != :lt do
        add_error(changeset, :close_time, "must be after open time")
      else
        changeset
      end
    else
      changeset
    end
  end
end
