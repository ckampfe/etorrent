defmodule Etorrent.TorrentWorker do
  use GenServer
  require Logger
  alias Etorrent.{Tracker, PeerWorker, DataFile}

  def start_link([torrent_file, _data_path] = args) do
    info_hash = Etorrent.info_hash(torrent_file)
    GenServer.start_link(__MODULE__, args, name: name(info_hash))
  end

  def all_info_hashes do
    Registry.select(Etorrent.Registry, [{{{__MODULE__, :"$1"}, :_, :_}, [], [:"$1"]}])
  end

  def get_metrics(info_hash) do
    GenServer.call(name(info_hash), :get_metrics)
  end

  def register_new_peer(info_hash, peer_pid, peer_id) do
    GenServer.call(name(info_hash), {:register_new_peer, peer_pid, peer_id})
  end

  def peer_have(info_hash, index) do
    GenServer.call(name(info_hash), {:peer_have, index})
  end

  def peer_bitfield(info_hash, bitfield) do
    GenServer.call(name(info_hash), {:peer_bitfield, bitfield})
  end

  ### CALLBACKS ###

  def init([torrent_file, data_path]) do
    peer_id_base = "-ET0001-"

    peer_id =
      Enum.reduce(1..12, peer_id_base, fn _, acc ->
        acc <> to_string(:rand.uniform(10) - 1)
      end)

    info_hash = Etorrent.info_hash(torrent_file)

    state = %{
      torrent_file: torrent_file,
      data_path: data_path,
      info_hash: info_hash,
      state: :active,
      peer_id: peer_id,
      port: 9000,
      # mapping of `piece index` -> `peer pid`
      peers_have_pieces: BiMultiMap.new()
    }

    Logger.metadata(
      info_hash: Base.encode16(info_hash) |> String.slice(0..5),
      name: torrent_file[:info][:name]
    )

    {:ok, state, {:continue, :setup}}
  end

  def handle_continue(:setup, state) do
    # TODO load state and configuration from disk
    Logger.debug("#{__MODULE__}: #{inspect(state)}")

    # {:ok, data_file} = :file.open(state[:data_path], [:read, :raw, :binary])
    {:ok, data_file} =
      Etorrent.DataFile.open_or_create(state[:data_path], state[:torrent_file][:info][:length])

    piece_hashes_and_lengths = DataFile.PieceHashes.new(state[:torrent_file][:info])

    pieces_statuses = DataFile.PieceHashes.verify_pieces(piece_hashes_and_lengths, data_file)

    state =
      state
      |> Map.put(:piece_hashes_and_lengths, piece_hashes_and_lengths)
      |> Map.put(:pieces_statuses, pieces_statuses)

    send(self(), :announce)
    send(self(), :tick)

    {:noreply, state}
  end

  def handle_call({:register_new_peer, peer_pid, peer_id}, _from, %{data_path: data_path} = state) do
    _peer_ref = Process.monitor(peer_pid)

    PeerWorker.give_peer_id(peer_pid, state[:peer_id], data_path)

    {:reply, :ok, state}
  end

  def handle_call(:get_metrics, _from, state) do
    {:reply,
     {:ok,
      %{
        info_hash: state[:info_hash] |> Base.encode16(),
        name: state[:torrent_file][:info][:name],
        size: state[:torrent_file][:info][:length],
        progress: 0,
        download: 0,
        upload: 0,
        # TODO
        peers: %{},
        ratio: 0.0,
        pieces: state[:pieces_statuses]
      }}, state}
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

    {:reply, :ok, state}
  end

  # TODO
  #
  # do we want to store peer choked/interested state in this process?
  # peer processes do not make the determination to download on their own
  # they are dumb, they should only begin downloading if commanded

  def handle_info(:announce, state) do
    Logger.debug("announcing to #{inspect(state[:torrent_file][:announce])}")

    # TODO FIX: for some reason announce is only returning this same peer. why?
    announce_response =
      case Tracker.announce(state[:torrent_file], state[:peer_id], state[:port],
             event: "started",
             left: state[:torrent_file][:info][:length]
           ) do
        {:ok, announce_response} ->
          announce_response =
            Map.update!(announce_response, :peers, fn peers ->
              Enum.filter(peers, fn %{"peer id": other_peer_id} ->
                other_peer_id != state.peer_id
              end)
            end)

          Process.send_after(self(), :announce, :timer.seconds(announce_response[:interval]))

          announce_response

        {:error, e} = error ->
          Logger.debug("Error announcing: #{inspect(e)}")
          Process.send_after(self(), :announce, :timer.minutes(3))
          error
      end

    state = Map.put(state, :announce_response, announce_response)

    {:noreply, state}
  end

  def handle_info(:tick, state) do
    # is there still work to do?
    # if so, schedule it
    # if not, do nothing

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      state
      |> Map.update!(:peers_have_pieces, fn peers_have_pieces ->
        BiMultiMap.delete_value(peers_have_pieces, pid)
      end)

    {:noreply, state}
  end

  ### PRIVATE ###

  defp name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end
end
