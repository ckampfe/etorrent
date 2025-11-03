defmodule Etorrent.TorrentSupervisor do
  use Supervisor
  require Logger
  alias Etorrent.{TorrentWorker, PeerSupervisor}

  def start_link([info_hash, _data_path] = args) do
    Supervisor.start_link(__MODULE__, args, name: name(info_hash))
  end

  @impl true
  def init([info_hash, _data_path] = args) do
    children = [
      {TorrentWorker, args},
      {PeerSupervisor, info_hash}
    ]

    Logger.debug("starting torrent children")

    Supervisor.init(children, strategy: :one_for_one)
  end

  def name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end
end
