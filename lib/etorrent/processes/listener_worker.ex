defmodule Etorrent.ListenerWorker do
  use GenServer
  require Logger

  defmodule State do
    defstruct [:listen_socket, port: Application.compile_env(:etorrent, :listen_port, 9000)]
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def get_listen_socket() do
    GenServer.call(__MODULE__, :get_listen_socket)
  end

  def init(_args) do
    {:ok, %State{}, {:continue, :listen}}
  end

  def handle_continue(:listen, %State{port: port} = state) do
    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false])

    Logger.debug("Listening for incoming peers on port #{port}")

    state = %{state | listen_socket: listen_socket}

    {:noreply, state}
  end

  def handle_call(:get_listen_socket, _from, %State{listen_socket: listen_socket} = state) do
    {:reply, {:ok, listen_socket}, state}
  end
end
