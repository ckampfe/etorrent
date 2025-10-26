defmodule Etorrent.ListenerWorker do
  use GenServer
  require Logger

  # TODO pass port as an option somehow
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{}, {:continue, :listen}}
  end

  def handle_continue(:listen, state) do
    port = 7777

    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false])

    Logger.debug("Listening on port #{port}")

    state = Map.put(state, :listen_socket, listen_socket)

    {:noreply, state}
  end

  def get_listen_socket() do
    GenServer.call(__MODULE__, :get_listen_socket)
  end

  def handle_call(:get_listen_socket, _from, state) do
    {:reply, state[:listen_socket], state}
  end
end
