defmodule RestaurantDash.Notifications.Notification do
  @moduledoc """
  Schema for a notification record — tracks every notification sent (or attempted).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_channels ~w(sms email push in_app)
  @valid_statuses ~w(pending sent failed)
  @valid_recipient_types ~w(customer driver owner staff)

  schema "notifications" do
    field :recipient_type, :string
    field :recipient_contact, :string
    field :channel, :string
    field :template, :string
    field :body, :string
    field :status, :string, default: "pending"
    field :sent_at, :utc_datetime
    field :error_message, :string

    belongs_to :restaurant, RestaurantDash.Tenancy.Restaurant
    belongs_to :order, RestaurantDash.Orders.Order

    timestamps(type: :utc_datetime)
  end

  def valid_channels, do: @valid_channels
  def valid_statuses, do: @valid_statuses
  def valid_recipient_types, do: @valid_recipient_types

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :restaurant_id,
      :order_id,
      :recipient_type,
      :recipient_contact,
      :channel,
      :template,
      :body,
      :status,
      :sent_at,
      :error_message
    ])
    |> validate_required([
      :restaurant_id,
      :recipient_type,
      :recipient_contact,
      :channel,
      :template,
      :body
    ])
    |> validate_inclusion(:channel, @valid_channels)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:recipient_type, @valid_recipient_types)
  end

  def sent_changeset(notification) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    notification
    |> cast(%{status: "sent", sent_at: now}, [:status, :sent_at])
  end

  def failed_changeset(notification, error_message) do
    notification
    |> cast(%{status: "failed", error_message: error_message}, [:status, :error_message])
  end
end
