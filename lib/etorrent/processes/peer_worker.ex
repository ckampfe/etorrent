# TODO
#
# - [x] figure out socket send timeouts
# - [x] figure out interest/choke state

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

  def request_block(server, piece_index, begin, block_length) do
    GenServer.call(server, {:request_block, piece_index, begin, block_length})
  end

  def we_have_piece(server, idx) do
    GenServer.cast(server, {:we_have_piece, idx})
  end

  def interested(server) do
    GenServer.call(server, :interested)
  end

  def not_interested(server) do
    GenServer.call(server, :not_interested)
  end

  def choke(server) do
    GenServer.call(server, :choke)
  end

  def unchoke(server) do
    GenServer.call(server, :unchoke)
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
      :remote_peer_id,
      :host,
      :port,
      :name
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

  def handle_call(
        {:request_block, piece_index, begin, length},
        _from,
        %State{socket: socket} = state
      ) do
    encoded_request =
      PeerProtocol.encode(%PeerProtocol.Request{index: piece_index, begin: begin, length: length})

    :ok = :gen_tcp.send(socket, encoded_request)

    {:reply, :ok, state}
  end

  def handle_call(:interested, _from, %State{socket: socket} = state) do
    encoded_interested = PeerProtocol.encode(%PeerProtocol.Interested{})
    :ok = :gen_tcp.send(socket, encoded_interested)
    {:reply, :ok, state}
  end

  def handle_call(:not_interested, _from, %State{socket: socket} = state) do
    encoded_not_interested = PeerProtocol.encode(%PeerProtocol.NotInterested{})
    :ok = :gen_tcp.send(socket, encoded_not_interested)
    {:reply, :ok, state}
  end

  def handle_call(:choke, _from, %State{socket: socket} = state) do
    encoded_choke = PeerProtocol.encode(%PeerProtocol.Choke{})
    :ok = :gen_tcp.send(socket, encoded_choke)
    {:reply, :ok, state}
  end

  def handle_call(:unchoke, _from, %State{socket: socket} = state) do
    encoded_unchoke = PeerProtocol.encode(%PeerProtocol.Unchoke{})
    :ok = :gen_tcp.send(socket, encoded_unchoke)
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
        %State{host: host, port: port, info_hash: info_hash, peer_id: peer_id} = state
      ) do
    {:ok, socket} = :gen_tcp.connect(host, port, [:binary, send_timeout: :timer.seconds(5)])

    handshake = PeerProtocol.encode_handshake(state[:info_hash], state[:peer_id])

    :ok = :gen_tcp.send(socket, handshake)

    handshake_result =
      case :gen_tcp.recv(socket, 1 + 19 + 8 + 20 + 20, :timer.seconds(5)) do
        {:ok,
         <<19, "BitTorrent protocol", _reserved::binary-size(8),
           remote_info_hash::binary-size(20), remote_peer_id::binary-size(20)>>} ->
          if remote_info_hash == info_hash do
            {:ok, remote_peer_id}
          else
            {:error, "info_hash does not match"}
          end

        {:error, _} = e ->
          e
      end

    case handshake_result do
      {:ok, remote_peer_id} ->
        {:ok, bitfield} = TorrentWorker.get_padded_bitfield(info_hash)

        encoded_bitfield = PeerProtocol.encode(%PeerProtocol.Bitfield{bitfield: bitfield})

        :ok = :gen_tcp.send(socket, encoded_bitfield)

        set_post_handshake_socket_mode(socket)

        state = %{state | socket: socket, remote_peer_id: remote_peer_id}

        {:noreply, state}

      {:error, error} ->
        {:stop, error, state}
    end
  end

  def handle_cast({:we_have_piece, idx}, %State{socket: socket} = state) do
    encoded_have = PeerProtocol.encode(%PeerProtocol.Have{index: idx})
    :ok = :gen_tcp.send(socket, encoded_have)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, _socket, data},
        %State{info_hash: info_hash, socket: socket, data_file: data_file} = state
      ) do
    {:ok, decoded} = PeerProtocol.decode(data)

    return =
      case decoded do
        %PeerProtocol.Choke{} ->
          Logger.debug("peer_choking: true")
          TorrentWorker.peer_choke(info_hash)
          {:noreply, state}

        %PeerProtocol.Unchoke{} ->
          Logger.debug("peer_choking: false")
          TorrentWorker.peer_unchoke(info_hash)
          {:noreply, state}

        %PeerProtocol.Interested{} ->
          Logger.debug("peer interested: true")
          TorrentWorker.peer_interested(info_hash)
          {:noreply, state}

        %PeerProtocol.NotInterested{} ->
          Logger.debug("peer interested: false")
          TorrentWorker.peer_not_interested(info_hash)
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

        %PeerProtocol.Piece{index: index, begin: begin, block: _chunk} = piece_message ->
          Logger.debug("received peer piece message #{index} #{begin} block")

          :ok = DataFile.write_block(info_hash, data_file, piece_message)

          {:ok, have?} = DataFile.verify_piece(info_hash, data_file, index)

          if have? do
            Logger.debug("have now have piece #{index}")
            :ok = TorrentWorker.we_have_piece(info_hash, index)
          end

          {:noreply, state}

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

  defp set_post_handshake_socket_mode(socket) do
    :ok =
      :inet.setopts(socket, [:binary, active: :once, packet: 4, send_timeout: :timer.seconds(5)])
  end

  defp make_active_once(socket) do
    :ok = :inet.setopts(socket, active: :once)
  end
end
