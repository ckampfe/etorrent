defmodule Etorrent do
  @moduledoc """
  Etorrent keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Etorrent.{TorrentWorker, PeerSupervisor, TorrentsSupervisor, Repo, Torrent, Bencode}
  import Ecto.Query
  require Logger

  def new_torrent(torrent_file, data_path) do
    info_hash = info_hash(torrent_file)

    # TODO any kind of path validation - but this assumes a trusted machine/user
    data_path = Path.join([data_path, torrent_file[:info][:name]])

    {:ok, encoded_torrent_file} =
      Bencode.encode(torrent_file)

    encoded_torrent_file = :erlang.iolist_to_binary(encoded_torrent_file)

    %Torrent{}
    |> Torrent.changeset(%{
      info_hash: info_hash,
      file: encoded_torrent_file,
      data_path: data_path
    })
    |> Repo.insert()

    TorrentsSupervisor.start_child(torrent_file, data_path)
  end

  def load_all_existing_torrents do
    Torrent
    |> select([:info_hash, :file, :data_path])
    |> Repo.all()
    # TODO parallelize
    |> Enum.each(fn torrent ->
      Logger.debug("Loading torrent #{Base.encode16(torrent.info_hash)}")
      {:ok, decoded_torrent_file} = Bencode.decode(torrent.file, atom_keys: true)
      TorrentsSupervisor.start_child(decoded_torrent_file, torrent.data_path)
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

  # must be called from the acceptorworker process,
  # gen_tcp.controlling_process/2 will error otherwise
  def add_incoming_peer_to_torrent(info_hash, peer_id, socket) do
    # 1. add peer to peersupervisor
    {:ok, peer_pid} =
      PeerSupervisor.start_peer_for_incoming_connection(info_hash, peer_id, socket)

    # 2. tell torrentworker about the peer, have it monitor the peer?
    :ok = TorrentWorker.register_new_peer(info_hash, peer_pid, peer_id)
    # 3. transfer the socket to the peer process
    :ok = :gen_tcp.controlling_process(socket, peer_pid)

    {:ok, info_hash}
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
