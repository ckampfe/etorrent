defmodule Etorrent.PeerSupervisor do
  use DynamicSupervisor
  alias Etorrent.PeerWorker

  def start_link(info_hash) do
    DynamicSupervisor.start_link(__MODULE__, info_hash, name: name(info_hash))
  end

  def start_peer_for_incoming_connection(info_hash, peer_id, socket) do
    name = name(info_hash)

    DynamicSupervisor.start_child(
      name,
      %{
        id: PeerWorker,
        start: {PeerWorker, :start_link_incoming_connection, [info_hash, peer_id, socket]},
        restart: :temporary
      }
    )
  end

  def start_peer_for_outgoing_connection(info_hash, peer_id, data_path, address, port) do
    name = name(info_hash)

    DynamicSupervisor.start_child(
      name,
      %{
        id: PeerWorker,
        start:
          {PeerWorker, :start_link_outgoing_connection,
           [
             %{
               info_hash: info_hash,
               peer_id: peer_id,
               data_path: data_path,
               address: address,
               port: port
             }
           ]},
        restart: :temporary
      }
    )
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end
end
