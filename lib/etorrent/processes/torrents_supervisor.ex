defmodule Etorrent.TorrentsSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_child(torrent_file) do
    DynamicSupervisor.start_child(__MODULE__, {Etorrent.TorrentSupervisor, torrent_file})
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
