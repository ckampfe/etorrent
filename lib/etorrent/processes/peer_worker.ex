# TODO
#
# - [x] figure out socket send timeouts
# - [x] figure out interest/choke state

defmodule Etorrent.PeerWorker do
  use GenServer
  require Logger
  alias Etorrent.{PeerProtocol, TorrentWorker, DataFile}

  def start_link_incoming_connection(args) do
    GenServer.start_link(__MODULE__, {:incoming_connection, args})
  end

  def start_link_outgoing_connection(args) do
    GenServer.start_link(__MODULE__, {:outgoing_connection, args})
  end

  def request_block(server, piece_index, begin, block_length) do
    GenServer.call(server, {:request_block, piece_index, begin, block_length})
  end

  def we_have_piece(server, piece_index) do
    GenServer.cast(server, {:we_have_piece, piece_index})
  end

  def interested(server) do
    GenServer.cast(server, :interested)
  end

  def not_interested(server) do
    GenServer.cast(server, :not_interested)
  end

  def choke(server) do
    GenServer.cast(server, :choke)
  end

  def unchoke(server) do
    GenServer.cast(server, :unchoke)
  end

  defmodule State do
    defstruct [
      :info_hash,
      :socket,
      :data_path,
      :data_file,
      :peer_id,
      :remote_peer_id,
      :address,
      :port
    ]
  end

  def init({mode, %{info_hash: info_hash} = args}) do
    state = %State{
      info_hash: info_hash,
      peer_id: Map.get(args, :peer_id),
      address: Map.get(args, :address),
      port: Map.get(args, :port),
      data_path: Map.get(args, :data_path),
      socket: Map.get(args, :socket)
    }

    Logger.metadata(info_hash: Base.encode16(info_hash) |> String.slice(0..5))

    Logger.debug("outgoing peer worker started")

    Process.send_after(self(), :keepalive, :timer.minutes(1))

    case mode do
      :incoming_connection ->
        {:ok, state}

      :outgoing_connection ->
        {:ok, state, {:continue, :open_peer_connection}}
    end
  end

  def give_peer_id(server, peer_id, data_path) do
    GenServer.call(server, {:give_peer_id, peer_id, data_path})
  end

  def reply_with_handshake(server, padded_bitfield) do
    GenServer.call(server, {:reply_with_handshake, padded_bitfield})
  end

  def handle_call(
        {:give_peer_id, peer_id, data_path},
        _from,
        %State{} = state
      ) do
    Logger.debug("in handle_call for give_peer_id")

    {:ok, data_file} = DataFile.open_or_create(data_path)

    state = %{state | peer_id: peer_id, data_path: data_path, data_file: data_file}

    {:reply, :ok, state}
  end

  def handle_call(
        {:request_block, piece_index, begin, length},
        _from,
        %State{socket: socket} = state
      ) do
    encoded_request =
      PeerProtocol.encode(%PeerProtocol.Request{index: piece_index, begin: begin, length: length})

    Logger.debug("requested piece #{piece_index} #{begin} #{length}")

    :ok = :gen_tcp.send(socket, encoded_request)

    {:reply, :ok, state}
  end

  def handle_call(
        {:reply_with_handshake, padded_bitfield},
        _from,
        %State{info_hash: info_hash, peer_id: peer_id, socket: socket} = state
      ) do
    handshake = PeerProtocol.encode_handshake(info_hash, peer_id)

    Logger.debug("incoming peer: replied with handshake")

    :ok = :gen_tcp.send(socket, handshake)

    set_post_handshake_socket_mode(socket)

    # {:ok, bitfield} = TorrentWorker.get_padded_bitfield(info_hash)

    encoded_bitfield = PeerProtocol.encode(%PeerProtocol.Bitfield{bitfield: padded_bitfield})

    :gen_tcp.send(socket, encoded_bitfield)

    Logger.debug("incoming peer: sent bitfield")

    {:reply, :ok, state}
  end

  # open socket
  # send handshake
  # wait for handshake reply
  # send bitfield
  def handle_continue(
        :open_peer_connection,
        %State{
          address: address,
          port: port,
          info_hash: info_hash,
          peer_id: peer_id,
          data_path: data_path
        } = state
      ) do
    with {_, {:ok, socket}} <-
           {:connect_to_socket,
            :gen_tcp.connect(address, port, [
              :binary,
              send_timeout: :timer.seconds(5),
              active: false
            ])},
         handshake = PeerProtocol.encode_handshake(info_hash, peer_id),
         {_, :ok} <- {:send_handshake, :gen_tcp.send(socket, handshake)},
         {_,
          {:ok,
           <<19, "BitTorrent protocol", _reserved::binary-size(8),
             remote_info_hash::binary-size(20), remote_peer_id::binary-size(20)>>}}
         when remote_info_hash == info_hash <-
           {:receive_handshake, :gen_tcp.recv(socket, 1 + 19 + 8 + 20 + 20, :timer.seconds(5))} do
      set_post_handshake_socket_mode(socket)
      {:ok, data_file} = DataFile.open_or_create(data_path)
      state = %{state | socket: socket, remote_peer_id: remote_peer_id, data_file: data_file}
      {:noreply, state}
    else
      {error_clause, e} ->
        Logger.debug(
          "#{inspect(address)}:#{port}: error during hanshake phase #{inspect(error_clause)}: #{inspect(e)}"
        )

        {:stop, :shutdown, state}
    end
  end

  def handle_cast({:we_have_piece, idx}, %State{socket: socket} = state) do
    encoded_have = PeerProtocol.encode(%PeerProtocol.Have{index: idx})
    :ok = :gen_tcp.send(socket, encoded_have)
    {:noreply, state}
  end

  def handle_cast(:choke, %State{socket: socket} = state) do
    encoded_choke = PeerProtocol.encode(%PeerProtocol.Choke{})
    :ok = :gen_tcp.send(socket, encoded_choke)
    Logger.debug("sent choke")
    {:noreply, state}
  end

  def handle_cast(:unchoke, %State{socket: socket} = state) do
    encoded_unchoke = PeerProtocol.encode(%PeerProtocol.Unchoke{})
    :ok = :gen_tcp.send(socket, encoded_unchoke)
    Logger.debug("sent unchoke")
    {:noreply, state}
  end

  def handle_cast(:interested, %State{socket: socket} = state) do
    encoded_interested = PeerProtocol.encode(%PeerProtocol.Interested{})
    :ok = :gen_tcp.send(socket, encoded_interested)
    Logger.debug("sent interested")
    {:noreply, state}
  end

  def handle_cast(:not_interested, %State{socket: socket} = state) do
    encoded_not_interested = PeerProtocol.encode(%PeerProtocol.NotInterested{})
    :ok = :gen_tcp.send(socket, encoded_not_interested)
    Logger.debug("sent not interested")
    {:noreply, state}
  end

  def handle_info(:keepalive, %State{socket: socket} = state) do
    encoded_keepalive = PeerProtocol.encode(%PeerProtocol.KeepAlive{})
    :ok = :gen_tcp.send(socket, encoded_keepalive)
    Process.send_after(self(), :keepalive, :timer.minutes(1))
    {:noreply, state}
  end

  def handle_info(
        {:tcp, _socket, data},
        %State{info_hash: info_hash, socket: socket, data_file: data_file} = state
      ) do
    {:ok, decoded} = PeerProtocol.decode(data)

    return =
      case decoded do
        %PeerProtocol.KeepAlive{} ->
          Logger.debug("keepalive")
          {:noreply, state}

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

        %PeerProtocol.Request{index: index, begin: block_begin, length: block_length} ->
          Logger.debug("peer request #{index} #{block_begin} #{block_length}")

          :ok =
            DataFile.send_piece(info_hash, data_file, index, block_begin, block_length, socket)

          Logger.debug("sent block #{index} #{block_begin} #{block_length}")

          TorrentWorker.sent_block_to_peer(info_hash, block_length)

          {:noreply, state}

        # TODO what should we actually do here after writing the data to disk?
        # should we handle verification here, or in the TorrentWorker?
        %PeerProtocol.Piece{index: index, begin: begin, block: chunk} = piece_message ->
          Logger.debug("received peer piece message #{index} #{begin} block")

          :ok = DataFile.write_block(info_hash, data_file, piece_message)

          TorrentWorker.peer_sent_block(info_hash, index, begin, byte_size(chunk))

          {:ok, have?} = DataFile.verify_piece(info_hash, data_file, index)

          if have? do
            Logger.debug("have now have piece #{index}")
            :ok = TorrentWorker.we_have_piece(info_hash, index)
          end

          {:noreply, state}

        %PeerProtocol.Cancel{index: index, begin: begin, length: length} ->
          Logger.debug("peer cancel #{index} #{begin} #{length}")
          # TODO
          # actually do something in response to Cancel messages?
          # does it matter?
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

    make_active_once(socket)

    return
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("socket closed")
    {:stop, :normal, state}
  end

  defp set_post_handshake_socket_mode(socket) do
    :ok =
      :inet.setopts(socket, [:binary, active: :once, packet: 4, send_timeout: :timer.seconds(5)])
  end

  defp make_active_once(socket) do
    :ok = :inet.setopts(socket, active: :once)
  end
end
