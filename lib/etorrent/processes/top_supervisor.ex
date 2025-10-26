defmodule Etorrent.TopSupervisor do
  use Supervisor
  alias Etorrent.{ListenerWorker, AcceptorSupervisor, TorrentsSupervisor, TorrentsLoader}

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {ListenerWorker, []},
      {AcceptorSupervisor, Application.fetch_env!(:etorrent, :acceptors)},
      {TorrentsSupervisor, []},
      {TorrentsLoader, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
