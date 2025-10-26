defmodule Etorrent.Torrent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "torrents" do
    field :info_hash, :binary
    field :file, :binary
    field :data_path, :string
    field :downloaded, :integer
    field :uploaded, :integer
    field :status, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(torrent, attrs) do
    torrent
    |> cast(attrs, [:info_hash, :file, :data_path, :downloaded, :uploaded])
    |> validate_required([:info_hash, :file])
    |> validate_inclusion(:status, ["paused", "started"])
    |> unique_constraint(:info_hash)
  end
end
