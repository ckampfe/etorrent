# need to figure out what state we need
# - what pieces we have
# - what pieces we want
# - what pieces peers have
# - what pieces we have requested from peers
#
# with operations:
# - [x] load our had/want pieces from disk on start (bitfield)
# - [ ] store that we now have a piece
# - [x] store that a peer has a piece
# - [x] store that we have requested a piece from a peer
# - [x] remove requests when a peer disconnects
# - [ ] remove requests when a peer chokes
# - [ ] track state of what peers are choking us
# - [i] get random "want" piece that we haven't already requested
# - [ ] store interested/choked status on this TorrentWorker rather than in each process
# - [ ] compute "left" amount being (length - have) to send to tracker
# - [ ] connect to peers after we get them from announce, if we are leaching

defmodule Etorrent.TorrentWorker do
  use GenServer
  require Logger
  alias Etorrent.{Tracker, PeerWorker, DataFile, TorrentFile}

  def start_link([info_hash, _data_path] = args) do
    GenServer.start_link(__MODULE__, args, name: name(info_hash))
  end

  def all_info_hashes do
    Registry.select(Etorrent.Registry, [{{{__MODULE__, :"$1"}, :_, :_}, [], [:"$1"]}])
  end

  def get_metrics(info_hash) do
    GenServer.call(name(info_hash), :get_metrics)
  end

  def get_padded_bitfield(info_hash) do
    GenServer.call(name(info_hash), :get_padded_bitfield)
  end

  def register_new_peer(info_hash, peer_pid, peer_id) do
    GenServer.call(name(info_hash), {:register_new_peer, peer_pid, peer_id})
  end

  def we_have_piece(info_hash, index) do
    GenServer.call(name(info_hash), {:we_have_piece, index})
  end

  def peer_have(info_hash, index) do
    GenServer.call(name(info_hash), {:peer_have, index})
  end

  def peer_bitfield(info_hash, bitfield) do
    GenServer.call(name(info_hash), {:peer_bitfield, bitfield})
  end

  ### CALLBACKS ###

  defmodule State do
    defstruct [
      :info_hash,
      :data_path,
      :port,
      :peer_id,
      :announce_response,
      # this bitfifeld is unpadded.
      # it is only padded to octects
      # when sent to peers
      piece_statuses: <<>>,
      # mapping of `piece index` -> `peer pid`
      peers_have_pieces: BiMultiMap.new(),
      # `peer pid` -> `piece index`
      requests: BiMultiMap.new(),
      state: :started
    ]
  end

  def init([info_hash, data_path]) do
    # TODO
    #
    # load state and config from database

    peer_id_base = "-ET0001-"

    peer_id =
      Enum.reduce(1..12, peer_id_base, fn _, acc ->
        acc <> to_string(:rand.uniform(10) - 1)
      end)

    state = %State{
      info_hash: info_hash,
      data_path: data_path,
      state: :started,
      peer_id: peer_id,
      port: 9000,
      piece_statuses: <<>>,
      peers_have_pieces: BiMultiMap.new(),
      requests: BiMultiMap.new()
    }

    Logger.metadata(
      info_hash: Base.encode16(info_hash) |> String.slice(0..5),
      name: TorrentFile.name(info_hash)
    )

    {:ok, state, {:continue, :setup}}
  end

  def handle_continue(:setup, %State{info_hash: info_hash, data_path: data_path} = state) do
    # TODO load state and configuration from disk
    Logger.debug("#{__MODULE__}: #{inspect(state)}")

    {:ok, data_file} =
      DataFile.open_or_create(
        data_path,
        TorrentFile.length(info_hash)
      )

    {:ok, piece_statuses} = DataFile.verify_all_pieces(info_hash, data_file)

    state = %{state | piece_statuses: piece_statuses}

    send(self(), :announce)
    send(self(), :tick)

    Process.send_after(self(), :clear_old_requests, :timer.seconds(5))

    {:noreply, state}
  end

  def handle_call(
        {:register_new_peer, peer_pid, _peer_id},
        _from,
        %State{data_path: data_path, peer_id: peer_id} = state
      ) do
    _peer_ref = Process.monitor(peer_pid)

    PeerWorker.give_peer_id(peer_pid, peer_id, data_path)

    {:reply, :ok, state}
  end

  def handle_call(
        :get_metrics,
        _from,
        %State{info_hash: info_hash, piece_statuses: piece_statuses} = state
      ) do
    {:ok, name} = TorrentFile.name(info_hash)
    {:ok, length} = TorrentFile.length(info_hash)

    {:reply,
     {:ok,
      %{
        info_hash: Base.encode16(info_hash),
        name: name,
        size: length,
        progress: 0,
        download: 0,
        upload: 0,
        # TODO
        peers: %{},
        ratio: 0.0,
        pieces: piece_statuses
      }}, state}
  end

  def handle_call(:get_padded_bitfield, _from, %State{piece_statuses: piece_statuses} = state) do
    length = bit_size(piece_statuses)

    padding = <<0::size(ceil(length / 8) * 8 - length)>>

    padded_bitfield = <<piece_statuses::bits, padding::bits>>

    {:reply, {:ok, padded_bitfield}, state}
  end

  def handle_call(
        {:we_have_piece, index},
        _from,
        %State{peers_have_pieces: peers_have_pieces} = state
      ) do
    state = %{
      state
      | piece_statuses: DataFile.set_bit(state.piece_statuses, index),
        requests: BiMultiMap.delete_value(state.requests, index)
    }

    peers = BiMultiMap.values(peers_have_pieces)

    Enum.each(peers, fn peer ->
      PeerWorker.we_have_piece(peer, index)
    end)

    {:reply, :ok, state}
  end

  def handle_call({:peer_have, index}, {peer_pid, _tag}, state) do
    state =
      Map.update!(state, :peers_have_pieces, fn mapping ->
        BiMultiMap.put(mapping, index, peer_pid)
      end)

    {:reply, :ok, state}
  end

  def handle_call({:peer_bitfield, bitfield}, {peer_pid, _tag} = _from, state) do
    # what do we want?
    #
    # we want to be able to say, efficiently:
    # - give me a peer that has this piece
    # - peer has disconnected: remove all pieces from "available pieces" for peer
    # - tell me a piece I don't have
    # - peer now has this piece
    #
    # bitfield is 1's and 0's corresponding to piece indexes
    #
    # idx -> [peer]
    #
    # but how do you efficiently remove peer in the case of disconnection?
    # you can't, it's linear in the number of indexes
    state =
      Map.update!(state, :peers_have_pieces, fn mapping ->
        for <<have::1 <- bitfield>>, reduce: {mapping, 0} do
          {acc, i} ->
            if have do
              {BiMultiMap.put(acc, i, peer_pid), i + 1}
            else
              {acc, i + 1}
            end
        end
      end)

    Process.send_after(self(), :tick, 100)

    {:reply, :ok, state}
  end

  # TODO
  #
  # do we want to store peer choked/interested state in this process?
  # peer processes do not make the determination to download on their own
  # they are dumb, they should only begin downloading if commanded

  def handle_info(:announce, %State{info_hash: info_hash, peer_id: peer_id, port: port} = state) do
    Logger.debug("announcing to #{inspect(TorrentFile.announce(info_hash))}")

    {:ok, length} = TorrentFile.length(info_hash)

    announce_response =
      case Tracker.announce(info_hash, peer_id, port,
             event: "started",
             # TODO compute real "left"
             left: length
           ) do
        {:ok, announce_response} ->
          announce_response =
            Map.update!(announce_response, :peers, fn peers ->
              Enum.filter(peers, fn %{"peer id": other_peer_id} ->
                other_peer_id != peer_id
              end)
            end)

          Process.send_after(self(), :announce, :timer.seconds(announce_response[:interval]))

          announce_response

        {:error, e} = error ->
          Logger.debug("Error announcing: #{inspect(e)}")
          Process.send_after(self(), :announce, :timer.minutes(3))
          error
      end

    state = %{state | announce_response: announce_response}

    {:noreply, state}
  end

  def handle_info(
        :tick,
        %{
          piece_statuses: piece_statuses,
          requests: requests,
          peers_have_pieces: peers_have_pieces
        } = state
      ) do
    # is there still work to do?
    # if so, schedule it
    # if not, do nothing

    # 1. pieces we want
    pieces_wanted =
      for <<i::1 <- piece_statuses>>, reduce: {[], 0} do
        {wants, current_i} ->
          if i == 0 do
            {[current_i | wants], current_i + 1}
          else
            {wants, current_i + 1}
          end
      end
      |> then(fn {wants, _} -> wants end)
      |> MapSet.new()

    # 2. pieces that aren't already requested
    requested_pieces = BiMultiMap.values(requests) |> MapSet.new()

    wanted_and_not_requested = MapSet.difference(pieces_wanted, requested_pieces)

    # 3. that are available
    available_pieces =
      peers_have_pieces
      |> BiMultiMap.keys()
      |> MapSet.new()

    wanted_available_and_not_requested =
      MapSet.intersection(wanted_and_not_requested, available_pieces)

    pieces_to_request = Enum.take(wanted_available_and_not_requested, 5)

    # TODO conditional to not do anything if no requests
    if Enum.empty?(pieces_to_request) do
      Logger.debug("no pieces to request, doing nothing this tick")
      Process.send_after(self(), :tick, :timer.seconds(3))
      {:noreply, state}
    else
      IO.inspect(pieces_to_request, label: "pieces to request")

      requests =
        pieces_to_request
        |> Enum.map(fn idx ->
          peer =
            peers_have_pieces
            |> BiMultiMap.get(idx)
            |> Enum.random()

          {peer, idx}
        end)
        |> BiMultiMap.new()

      Enum.each(requests, fn {peer, idx} ->
        PeerWorker.request_piece(peer, idx)
        Logger.debug("asked peer #{inspect(peer)} to request piece #{idx}")
      end)

      state = Map.put(state, :requests, requests)

      Process.send_after(self(), :tick, :timer.seconds(1))

      {:noreply, state}
    end
  end

  def handle_info(:clear_old_requests, %State{} = state) do
    state =
      if BiMultiMap.size(state.requests) > 0 do
        Logger.debug("cleared old requests")
        Map.put(state, :requests, BiMultiMap.new())
      else
        Logger.debug("no old requests")
        state
      end

    Process.send_after(self(), :clear_old_requests, :timer.seconds(3))

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # TODO send cancel messages to peers so they cancel their block requests
    state =
      state
      |> Map.update!(:peers_have_pieces, fn peers_have_pieces ->
        BiMultiMap.delete_value(peers_have_pieces, pid)
      end)
      |> Map.update!(:requests, fn requests ->
        BiMultiMap.delete(requests, pid)
      end)

    {:noreply, state}
  end

  # TODO actually set up a separate process to monitor this process
  # and perform this cleanup there
  def terminate(_reason, %State{info_hash: info_hash}) do
    TorrentFile.delete(info_hash)
    :ok
  end

  ### PRIVATE ###

  defp name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end
end
