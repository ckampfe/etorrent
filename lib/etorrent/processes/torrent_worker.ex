# - how to tell which peers to download which pieces?
#
# - store a mapping of %{peer_id => [piece_index]}
#
# - for every index we don't have, pick a random peer.
#
# - store a list that at each index includes a set of peers that have that index
# [%MapSet([id1, id2, id3, etc.]), etc.]
# - keep this up to date when we receive "have" messages from peers.
# - have peers forward the initial bitfield message to this process.
#
# - store a list of actively downloading pieces, and what peer is downloading them
# - have a timer that times them out after a period of time
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
      peers: %{},
      peer_id: peer_id,
      port: 7777,
      pieces_have: [],
      pieces_want: []
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

    # torrent =
    #   Torrent
    #   |> where([m], m.info_hash == ^state[:info_hash])
    #   |> Repo.one()

    # torrent =
    #   if meta do
    #     meta
    #   else
    #     Repo.insert(%Torrent{info_hash: state[:info_hash]})
    #   end

    # piece_hashes_and_lengths = calculate_piece_lengths(state[:torrent_file][:info])

    {:ok, data_file} = :file.open(state[:data_path], [:read, :raw, :binary])

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

  def handle_call({:register_new_peer, peer_pid, peer_id}, _from, state) do
    peer_ref = Process.monitor(peer_pid)

    state =
      Map.update!(state, :peers, fn peers ->
        Map.put(peers, peer_id, {peer_pid, peer_ref})
      end)

    PeerWorker.give_peer_id(peer_pid, state[:peer_id])

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
        peers: state[:peers],
        ratio: 0.0,
        pieces: state[:pieces_statuses]
      }}, state}
  end

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

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    peers =
      state[:peers]
      |> Enum.filter(fn {_peer_id, peer_pid_and_ref} ->
        peer_pid_and_ref != {ref, pid}
      end)
      |> Map.new()

    state = Map.put(state, :peers, peers)

    {:noreply, state}
  end

  defp name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end
end
