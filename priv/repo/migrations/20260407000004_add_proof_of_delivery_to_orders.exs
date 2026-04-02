defmodule RestaurantDash.Repo.Migrations.AddProofOfDeliveryToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :delivery_photo, :text
      add :delivery_signature, :text
      add :driver_rating, :integer
      add :driver_rating_comment, :string
    end
  end
end
