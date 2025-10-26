defmodule Etorrent.Repo.Migrations.CreateTorrents do
  use Ecto.Migration

  def change do
    create table(:torrents) do
      add :info_hash, :binary
      add :file, :binary
      add :data_path, :string
      add :downloaded, :integer
      add :uploaded, :integer
      add :status, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:torrents, [:info_hash])
  end
end
