defmodule Etorrent.PeerWorker do
  use GenServer, restart: :temporary
  require Logger
  alias Etorrent.{PeerProtocol, TorrentWorker, DataFile}

  def start_link_incoming_connection(args) do
    GenServer.start_link(__MODULE__, {:incoming, args})
  end

  def start_link_outgoing_connection(args) do
    GenServer.start_link(__MODULE__, {:outoing, args})
  end

  def request_piece(server, piece_idx) do
    GenServer.call(server, {:request_piece, piece_idx})
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

  defmodule State do
    defstruct [
      :info_hash,
      :socket,
      :data_path,
      :data_file,
      :peer_id,
      :host,
      :port,
      :name,
      am_choking: true,
      am_interested: false,
      peer_choking: true,
      peer_interested: false
    ]
  end

  def init({mode, %{info_hash: info_hash, name: name} = args}) do
    state = %State{
      info_hash: info_hash,
      name: name
    }

    Logger.metadata(
      info_hash: Base.encode16(info_hash) |> String.slice(0..5),
      name: name
    )

    Logger.debug("outgoing peer worker started")

    case mode do
      :incoming ->
        {:ok, state, {:continue, :reply_with_handshake}}

      :outgoing ->
        {:ok, state, {:continue, :open_peer_connection}}
    end
  end

  def give_peer_id(server, peer_id, data_path) do
    GenServer.call(server, {:give_peer_id, peer_id, data_path})
  end

  def handle_call(
        {:give_peer_id, peer_id, data_path},
        _from,
        %State{data_path: data_path} = state
      ) do
    {:ok, f} = DataFile.open_or_create(data_path)

    state = %{state | peer_id: peer_id, data_path: data_path, data_file: f}

    {:reply, :ok, state}
  end

  def handle_call({:request_piece, piece_idx}, _from, %{socket: socket} = state) do
    Logger.debug("peer #{inspect(self())} requesting piece #{piece_idx}")

    # TODO mechanism to get chunks
    encoded_request =
      PeerProtocol.encode(%PeerProtocol.Request{index: piece_idx, begin: 0, length: 0})

    :gen_tcp.send(socket, encoded_request)

    {:reply, :ok, state}
  end

  def handle_continue(
        :reply_with_handshake,
        %{info_hash: info_hash, peer_id: peer_id, socket: socket} = state
      ) do
    handshake = PeerProtocol.encode_handshake(info_hash, peer_id)

    :ok = :gen_tcp.send(socket, handshake)

    set_post_handshake_socket_mode(socket)

    {:ok, bitfield} = TorrentWorker.get_padded_bitfield(info_hash)

    encoded_bitfield = PeerProtocol.encode(%PeerProtocol.Bitfield{bitfield: bitfield})

    :gen_tcp.send(socket, encoded_bitfield)

    state = Map.put(state, :socket, socket)

    {:noreply, state}
  end

  # open socket
  # send handshake
  # wait for handshake reply
  # send bitfield
  def handle_continue(
        :open_peer_connection,
        %State{host: host, port: port} = state
      ) do
    {:ok, socket} = :gen_tcp.connect(host, port, [:binary])

    handshake = PeerProtocol.encode_handshake(state[:info_hash], state[:peer_id])

    :ok = :gen_tcp.send(socket, handshake)

    set_post_handshake_socket_mode(socket)

    state = %{state | socket: socket}

    {:noreply, state}
  end

  def handle_info(
        {:tcp, _socket, data},
        %State{info_hash: info_hash, socket: socket} = state
      ) do
    {:ok, decoded} = PeerProtocol.decode(data)

    return =
      case decoded do
        %PeerProtocol.Choke{} ->
          Logger.debug("peer_choking: true")
          state = Map.put(state, :peer_choking, true)
          {:noreply, state}

        %PeerProtocol.Unchoke{} ->
          Logger.debug("peer_choking: false")
          state = Map.put(state, :peer_choking, false)
          {:noreply, state}

        %PeerProtocol.Interested{} ->
          Logger.debug("peer interested: true")
          state = Map.put(state, :peer_interested, true)
          {:noreply, state}

        %PeerProtocol.NotInterested{} ->
          Logger.debug("peer interested: false")
          state = Map.put(state, :peer_interested, false)
          {:noreply, state}

        %PeerProtocol.Have{index: index} ->
          Logger.debug("peer have #{index}")
          TorrentWorker.peer_have(info_hash, index)
          {:noreply, state}

        %PeerProtocol.Bitfield{bitfield: bitfield} ->
          Logger.debug("peer bitfield")
          TorrentWorker.peer_bitfield(info_hash, bitfield)
          {:noreply, state}

        %PeerProtocol.Request{index: index, begin: begin, length: length} ->
          Logger.debug("peer request #{index} #{begin} #{length}")
          raise "todo"

        %PeerProtocol.Piece{index: index, begin: begin, block: block} ->
          Logger.debug("peer piece #{index} #{begin} block")
          # TODO fix this
          # Etorrent.DataFile.write_block(state[:file], )
          raise "todo"

        %PeerProtocol.Cancel{index: index, begin: begin, length: length} ->
          Logger.debug("peer cancel #{index} #{begin} #{length}")
          raise "todo"

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

    make_active_once(socket)

    return
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("socket closed")
    {:noreply, state}
  end

  def set_post_handshake_socket_mode(socket) do
    :ok = :inet.setopts(socket, [:binary, active: :once, packet: 4])
  end

  defp make_active_once(socket) do
    :ok = :inet.setopts(socket, active: :once)
  end
end
