defmodule Etorrent.PeerWorker do
  use GenServer, restart: :temporary
  require Logger
  alias Etorrent.PeerProtocol

  def start_link_incoming_connection(args) do
    GenServer.start_link(__MODULE__, {:incoming, args})
  end

  def start_link_outgoing_connection(args) do
    GenServer.start_link(__MODULE__, {:outoing, args})
  end

  # def init({:incoming, args}) do
  #   state = %{
  #     tcp_module: Application.fetch_env!(:etorrent, __MODULE__)[:tcp_module],
  #     inet_module: Application.fetch_env!(:etorrent, __MODULE__)[:inet_module],
  #     am_choking: true,
  #     am_interested: false,
  #     peer_choking: true,
  #     peer_interested: false
  #   }

  #   Logger.debug("incoming peer worker started")

  #   {:ok, state}
  # end

  def init({mode, args}) do
    state = %{
      tcp_module: Application.fetch_env!(:etorrent, __MODULE__)[:tcp_module],
      inet_module: Application.fetch_env!(:etorrent, __MODULE__)[:inet_module],
      am_choking: true,
      am_interested: false,
      peer_choking: true,
      peer_interested: false
    }

    Logger.debug("outgoing peer worker started")

    case mode do
      :incoming ->
        {:ok, state, {:continue, :reply_with_handshake}}

      :outgoing ->
        {:ok, state, {:continue, :open_peer_connection}}
    end
  end

  def give_peer_id(server, peer_id) do
    GenServer.call(server, {:give_peer_id, peer_id})
  end

  def handle_call({:give_peer_id, peer_id}, _from, state) do
    state = Map.put(state, :peer_id, peer_id)
    {:reply, :ok, state}
  end

  def handle_continue(
        :reply_with_handshake,
        %{tcp_module: tcp_module, inet_module: inet_module, socket: socket} = state
      ) do
    handshake = PeerProtocol.encode_handshake(state[:info_hash], state[:peer_id])

    :ok = tcp_module.send(socket, handshake)

    set_post_handshake_socket_mode(socket, inet_module)

    state = Map.put(state, :socket, socket)

    {:noreply, state}
  end

  # open socket
  # send handshake
  # wait for handshake reply
  # send bitfield
  def handle_continue(
        :open_peer_connection,
        %{tcp_module: tcp_module, inet_module: inet_module, host: host, port: port} = state
      ) do
    {:ok, socket} = tcp_module.connect(host, port, [:binary])

    handshake = PeerProtocol.encode_handshake(state[:info_hash], state[:peer_id])

    :ok = tcp_module.send(socket, handshake)

    set_post_handshake_socket_mode(socket, inet_module)

    state = Map.put(state, :socket, socket)

    {:noreply, state}
  end

  def handle_info(
        {:tcp, _socket, data},
        %{info_hash: info_hash, socket: socket, inet_module: inet_module} = state
      ) do
    {:ok, decoded} = PeerProtocol.decode(data)

    return =
      case decoded do
        %PeerProtocol.Bitfield{bitfield: _bitfield} ->
          {:noreply, state}

        %PeerProtocol.Handshake{info_hash: remote_info_hash, peer_id: _remote_peer_id} ->
          if remote_info_hash == info_hash do
            {:noreply, state}
          else
            {:stop, :normal, state}
          end

        other ->
          Logger.debug("no handler yet for #{inspect(other)}")
          {:noreply, state}
      end

    Logger.debug("received data #{inspect(decoded)}")

    make_active_once(socket, inet_module)

    return
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:noreply, state}
  end

  def set_post_handshake_socket_mode(socket, inet_module) do
    inet_module.setopts(socket, [:binary, active: :once, packet: 4])
  end

  defp make_active_once(socket, inet_module) do
    inet_module.setopts(socket, active: :once)
  end
end
