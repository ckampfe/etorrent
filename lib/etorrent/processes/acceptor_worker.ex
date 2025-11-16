defmodule Etorrent.AcceptorWorker do
  use GenServer
  require Logger
  alias Etorrent.{ListenerWorker, PeerProtocol, PeerSupervisor, TorrentWorker}

  defmodule State do
    defstruct [:listen_socket, :i]
  end

  def child_spec(init_arg) do
    %{
      id: id(init_arg),
      start: {__MODULE__, :start_link, [%{i: init_arg}]}
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: id(args[:i]))
  end

  def init(%{i: i} = args) do
    Logger.debug("acceptor args #{inspect(args)}")
    {:ok, %State{i: i}, {:continue, :fetch_listen_socket}}
  end

  def handle_continue(:fetch_listen_socket, %State{} = state) do
    {:ok, listen_socket} = ListenerWorker.get_listen_socket()

    state = %{state | listen_socket: listen_socket}

    send(self(), :accept)

    {:noreply, state}
  end

  def handle_info(:accept, %State{listen_socket: listen_socket} = state) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)

    case :gen_tcp.recv(socket, 1 + 19 + 8 + 20 + 20, :timer.seconds(5)) do
      {:ok, bytes} ->
        {:ok, %PeerProtocol.Handshake{info_hash: info_hash, peer_id: peer_id}} =
          PeerProtocol.decode_handshake(bytes)

        {:ok, {address, port}} = :inet.peername(socket)

        add_incoming_peer_to_torrent(info_hash, peer_id, socket, address, port)

        send(self(), :accept)

      error ->
        Logger.warning("error receiving from incoming peer: #{inspect(error)}")
        send(self(), :accept)
    end

    {:noreply, state}
  end

  # must be called from the acceptorworker process,
  # gen_tcp.controlling_process/2 will error otherwise
  defp add_incoming_peer_to_torrent(info_hash, peer_id, socket, address, port) do
    # 1. add peer to peersupervisor
    {:ok, peer_pid} =
      PeerSupervisor.start_peer_for_incoming_connection(info_hash, peer_id, socket)

    # 2. tell torrentworker about the peer, have it monitor the peer?
    :ok = TorrentWorker.register_new_peer(info_hash, peer_pid, peer_id, address, port)
    # 3. transfer the socket to the peer process
    :ok = :gen_tcp.controlling_process(socket, peer_pid)

    {:ok, info_hash}
  end

  defp id(i) do
    :"#{__MODULE__}#{i}"
  end
end
