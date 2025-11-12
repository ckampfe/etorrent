defmodule Etorrent do
  @moduledoc """
  Etorrent keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Etorrent.{
    TorrentWorker,
    PeerSupervisor,
    TorrentsSupervisor,
    Repo,
    Torrent,
    Bencode,
    TorrentFile
  }

  import Ecto.Query
  require Logger

  def new_torrent(torrent_binary, data_path) when is_binary(torrent_binary) do
    {:ok, info_hash} = TorrentFile.new(torrent_binary)

    # TODO any kind of path validation - but this assumes a trusted machine/user
    {:ok, torrent_name} = TorrentFile.name(info_hash)
    data_path = Path.join([data_path, torrent_name])

    %Torrent{}
    |> Torrent.changeset(%{
      info_hash: info_hash,
      file: torrent_binary,
      data_path: data_path
    })
    |> Repo.insert()

    TorrentsSupervisor.start_child(info_hash, data_path)
  end

  def load_all_existing_torrents do
    Torrent
    |> select([:info_hash, :file, :data_path])
    |> Repo.all()
    # TODO parallelize
    |> Enum.each(fn torrent ->
      Logger.debug("Loading torrent #{Base.encode16(torrent.info_hash)}")
      {:ok, _info_hash} = TorrentFile.new(torrent.file)
      TorrentsSupervisor.start_child(torrent.info_hash, torrent.data_path)
    end)
  end

  def get_all_torrent_metrics do
    TorrentWorker.all_info_hashes()
    |> Enum.map(fn info_hash ->
      {:ok, metrics} = TorrentWorker.get_metrics(info_hash)
      metrics
    end)
  end

  def get_torrent_metrics(info_hash) do
    TorrentWorker.get_metrics(info_hash)
  end

  def info_hash(%{info: info}) do
    info
    |> Bencode.encode()
    |> then(fn {:ok, encoded} ->
      bin = :erlang.iolist_to_binary(encoded)
      :crypto.hash(:sha, bin)
    end)
  end
end
