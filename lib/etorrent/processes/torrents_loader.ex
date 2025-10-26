defmodule Etorrent.TorrentsLoader do
  use GenServer, restart: :transient
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, args, {:continue, :load_existing_torrents}}
  end

  def handle_continue(:load_existing_torrents, state) do
    Etorrent.load_all_existing_torrents()
    # shutdown when done - this is only needed at startup
    {:stop, :normal, state}
  end

  def terminate(reason, state) do
    Logger.debug("shutting down #{__MODULE__}: reason #{reason} state: #{inspect(state)}")
  end
end
