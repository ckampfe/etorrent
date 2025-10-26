defmodule Etorrent.PeerSupervisor do
  use DynamicSupervisor
  alias Etorrent.PeerWorker

  def start_link(torrent_file) do
    info_hash = info_hash(torrent_file)
    DynamicSupervisor.start_link(__MODULE__, torrent_file, name: name(info_hash))
  end

  def start_peer_for_incoming_connection(info_hash, peer_id, socket) do
    name = name(info_hash)

    DynamicSupervisor.start_child(
      name,
      %{
        id: PeerWorker,
        start: {PeerWorker, :start_link_incoming_connection, [info_hash, peer_id, socket]}
      }
    )
  end

  def start_peer_for_outgoing_connection(info_hash, peer_id) do
    name = name(info_hash)

    DynamicSupervisor.start_child(
      name,
      %{
        id: PeerWorker,
        start: {PeerWorker, :start_link_outgoing_connection, [info_hash, peer_id]}
      }
    )
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end

  defp info_hash(%{info: info}) do
    info
    |> Etorrent.Bencode.encode()
    |> then(fn {:ok, encoded} ->
      :crypto.hash(:sha, encoded)
    end)
  end
end
