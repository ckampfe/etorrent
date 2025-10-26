defmodule Etorrent.AcceptorWorker do
  use GenServer
  require Logger
  alias Etorrent.{ListenerWorker, PeerProtocol}

  def child_spec(init_arg) do
    %{
      id: id(init_arg),
      start: {__MODULE__, :start_link, [%{i: init_arg}]}
    }
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: id(args[:i]))
  end

  def init(args) do
    Logger.debug("acceptor args #{inspect(args)}")
    {:ok, args, {:continue, :fetch_listen_socket}}
  end

  def handle_continue(:fetch_listen_socket, state) do
    listen_socket = ListenerWorker.get_listen_socket()

    state = Map.put(state, :listen_socket, listen_socket)

    send(self(), :accept)

    {:noreply, state}
  end

  def handle_info(:accept, state) do
    {:ok, socket} = :gen_tcp.accept(state[:listen_socket])

    case :gen_tcp.recv(socket, 0) do
      {:ok, bytes} ->
        {:ok, %PeerProtocol.Handshake{info_hash: info_hash, peer_id: peer_id}} =
          PeerProtocol.decode_handshake(bytes)

        Etorrent.add_incoming_peer_to_torrent(info_hash, peer_id, socket)

        send(self(), :accept)

      error ->
        Logger.warning("error receiving from incoming peer: #{inspect(error)}")
        send(self(), :accept)
    end

    {:noreply, state}
  end

  defp id(i) do
    :"#{__MODULE__}#{i}"
  end
end
