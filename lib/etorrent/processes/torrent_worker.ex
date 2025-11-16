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
# - [ ] figure out interest/choke state:
#       if peer has pieces we don't have, we are interested in it, otherwise not.
#       if we are interested in peer and peer is not choking us: request from it
#       if peer is interested in us and we are not choking it: allow it to request from us
# - [x] we need to tell peer connections to request blocks, not pieces,
# -     have peer connections just be dumb and request what they're told

defmodule Etorrent.TorrentWorker do
  use GenServer
  require Logger
  alias Etorrent.PeerSupervisor
  alias Etorrent.{Tracker, PeerWorker, DataFile, TorrentFile}

  ### PUBLIC API ###

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

  def register_new_peer(info_hash, peer_pid, peer_id, address, port) do
    GenServer.call(name(info_hash), {:register_new_peer, peer_pid, peer_id, address, port})
  end

  def peer_choke(info_hash) do
    GenServer.call(name(info_hash), :peer_choke)
  end

  def peer_unchoke(info_hash) do
    GenServer.call(name(info_hash), :peer_unchoke)
  end

  def peer_interested(info_hash) do
    GenServer.call(name(info_hash), :peer_interested)
  end

  def peer_not_interested(info_hash) do
    GenServer.call(name(info_hash), :peer_not_interested)
  end

  def peer_sent_block(info_hash, piece_index, begin, block_length) do
    GenServer.call(name(info_hash), {:peer_sent_block, piece_index, begin, block_length})
  end

  def sent_block_to_peer(info_hash, block_length) do
    GenServer.call(name(info_hash), {:sent_block_to_peer, block_length})
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

  ### END PUBLIC API ###

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
      # `peer_pid -> peer_id`
      peer_pid_peer_id: BiMap.new(),
      # `peer_pid -> {address, port}`
      peer_pid_address_port: BiMap.new(),
      # mapping of `peer_pid` -> `%{
      #   interested_in_peer: bool,
      #   choking_peer: bool,
      #   peer_is_interested_in_us: bool,
      #   peer_is_choking_us: bool
      # }`
      peer_statuses: %{},
      # `peer pid` -> `piece index`
      # requests: BiMultiMap.new(),
      # `peer pid` -> `{piece_index, begin, length}` (block)
      inflight_requests: BiMultiMap.new(),
      state: :started,
      block_length: Application.compile_env(:etorrent, :block_length, 2 ** 15),
      inflight_requests_target: Application.compile_env(:etorrent, :inflight_requests_target, 5),
      maximum_uploads: Application.compile_env(:etorrent, :maximum_uploads, 4)
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
      peer_statuses: %{}
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

    {:ok, length} =
      TorrentFile.length(info_hash)

    {:ok, data_file} =
      DataFile.open_or_create(
        data_path,
        length
      )

    {:ok, piece_statuses} = DataFile.verify_all_pieces(info_hash, data_file)

    state = %{state | piece_statuses: piece_statuses}

    send(self(), :announce)
    send(self(), :request_tick)
    send(self(), :unchoke_tick)

    Process.send_after(self(), :clear_old_inflight_requests, :timer.seconds(30))

    {:noreply, state}
  end

  def handle_call(
        {:register_new_peer, peer_pid, peer_id, address, port},
        _from,
        %State{data_path: data_path, peer_id: peer_id} = state
      ) do
    _peer_ref = Process.monitor(peer_pid)

    PeerWorker.give_peer_id(peer_pid, peer_id, data_path)

    state =
      put_in(state, [:peer_statuses, peer_pid], %{
        interested_in_peer: false,
        choking_peer: true,
        peer_is_interested_in_us: false,
        peer_is_choking_us: true
      })

    state = %{
      state
      | peer_pid_peer_id: BiMap.put(state.peer_pid_peer_id, peer_pid, peer_id),
        peer_pid_address_port: BiMap.put(state.peer_pid_address_port, peer_pid, {address, port})
    }

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

  def handle_call(
        {:peer_sent_block, piece_index, begin, block_length},
        {peer_pid, _tag},
        %State{} = state
      ) do
    Logger.debug("peer #{inspect(peer_pid)} sent us a block of #{block_length}")

    state = %{
      state
      | inflight_requests:
          BiMultiMap.delete_value(state.inflight_requests, {piece_index, begin, block_length})
    }

    # TODO update some upload rate state for a peer here,
    # but for now do nothing

    {:reply, :ok, state}
  end

  def handle_call({:sent_block_to_peer, _block_length}, {_peer_pid, _tag}, state) do
    # TODO update some download rate state for a peer here,
    # but for now do nothing
    {:reply, :ok, state}
  end

  def handle_call(:get_padded_bitfield, _from, %State{piece_statuses: piece_statuses} = state) do
    length = bit_size(piece_statuses)

    padding = <<0::size(ceil(length / 8) * 8 - length)>>

    padded_bitfield = <<piece_statuses::bits, padding::bits>>

    {:reply, {:ok, padded_bitfield}, state}
  end

  def handle_call(:peer_choke, {peer_pid, _tag}, %State{} = state) do
    # state = put_in(state, [:peer_statuses, peer_pid, :peer_is_choking_us], true)
    state = %{
      state
      | peer_statuses: put_in(state.peer_statuses, [peer_pid, :peer_is_choking_us], true)
    }

    {:reply, :ok, state}
  end

  def handle_call(:peer_unchoke, {peer_pid, _tag}, state) do
    # state = put_in(state, [:peer_statuses, peer_pid, :peer_is_choking_us], false)
    state = %{
      state
      | peer_statuses: put_in(state.peer_statuses, [peer_pid, :peer_is_choking_us], false)
    }

    {:reply, :ok, state}
  end

  def handle_call(:peer_interested, {peer_pid, _tag}, state) do
    # state = put_in(state, [:peer_statuses, peer_pid, :peer_is_interested_in_us], true)
    state = %{
      state
      | peer_statuses: put_in(state.peer_statuses, [peer_pid, :peer_is_interested_in_us], true)
    }

    {:reply, :ok, state}
  end

  def handle_call(:peer_not_interested, {peer_pid, _tag}, state) do
    # state = put_in(state, [:peer_statuses, peer_pid, :peer_is_interested_in_us], false)
    state = %{
      state
      | peer_statuses: put_in(state.peer_statuses, [peer_pid, :peer_is_interested_in_us], false)
    }

    {:reply, :ok, state}
  end

  def handle_call(
        {:we_have_piece, piece_index},
        _from,
        %State{peers_have_pieces: peers_have_pieces} = state
      ) do
    state = %{
      state
      | piece_statuses: DataFile.set_bit(state.piece_statuses, piece_index)
        # requests: BiMultiMap.delete_value(state.requests, piece_index),
        # `peer pid` -> `{piece_index, begin, length}` (block)
        # inflight_requests: BiMultiMap
    }

    # TODO remove all outstanding inflight_requests that have the piece_index

    peers = BiMultiMap.values(peers_have_pieces)

    Enum.each(peers, fn peer ->
      PeerWorker.we_have_piece(peer, piece_index)
    end)

    {:reply, :ok, state}
  end

  def handle_call(
        {:peer_have, index},
        {peer_pid, _tag},
        %State{piece_statuses: piece_statuses} = state
      ) do
    state =
      Map.update!(state, :peers_have_pieces, fn peers_have_pieces ->
        BiMultiMap.put(peers_have_pieces, index, peer_pid)
      end)

    # does peer have piece we don't have?
    peer_haves =
      state.peers_have_pieces
      |> BiMultiMap.get_keys(peer_pid)
      |> MapSet.new()

    {wants, _} =
      for <<piece::1 <- piece_statuses>>, reduce: {MapSet.new(), 0} do
        {wants, i} ->
          if piece == 0 do
            {MapSet.put(wants, i), i + 1}
          else
            {wants, i + 1}
          end
      end

    interested_in_peer? = !Enum.empty?(MapSet.intersection(wants, peer_haves))

    previously_interested_in_peer? =
      get_in(state, [:peer_statuses, peer_pid, :interested_in_peer])

    state =
      case {interested_in_peer?, previously_interested_in_peer?} do
        {true, true} ->
          state

        {true, false} ->
          PeerWorker.interested(peer_pid)
          put_in(state, [:peer_statuses, peer_pid, :interested_in_peer], true)

        {false, true} ->
          PeerWorker.not_interested(peer_pid)
          put_in(state, [:peer_statuses, peer_pid, :interested_in_peer], false)

        {false, false} ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call(
        {:peer_bitfield, bitfield},
        {peer_pid, _tag} = _from,
        %State{piece_statuses: piece_statuses, peers_have_pieces: peers_have_pieces} = state
      ) do
    {peers_have_pieces, _} =
      for <<have::1 <- bitfield>>, reduce: {peers_have_pieces, 0} do
        {acc, i} ->
          if have do
            {BiMultiMap.put(acc, i, peer_pid), i + 1}
          else
            {acc, i + 1}
          end
      end

    state = %{state | peers_have_pieces: peers_have_pieces}

    peer_haves =
      state.peers_have_pieces
      |> BiMultiMap.get_keys(peer_pid)
      |> MapSet.new()

    {wants, _} =
      for <<piece::1 <- piece_statuses>>, reduce: {MapSet.new(), 0} do
        {wants, i} ->
          if piece == 0 do
            {MapSet.put(wants, i), i + 1}
          else
            {wants, i + 1}
          end
      end

    interested_in_peer? = !Enum.empty?(MapSet.intersection(wants, peer_haves))

    state =
      if interested_in_peer? do
        Logger.debug("interested in peer after bitfield")
        PeerWorker.interested(peer_pid)
        # put_in(state, [:peer_statuses, peer_pid, :interested_in_peer], true)
        %{
          state
          | peer_statuses: put_in(state.peer_statuses, [peer_pid, :interested_in_peer], true)
        }
      else
        Logger.debug("not interested in peer after bitfield")
        state
      end

    Process.send_after(self(), :request_tick, 100)

    {:reply, :ok, state}
  end

  # TODO
  #
  # do we want to store peer choked/interested state in this process?
  # peer processes do not make the determination to download on their own
  # they are dumb, they should only begin downloading if commanded

  def handle_info(
        :announce,
        %State{
          info_hash: info_hash,
          peer_id: peer_id,
          port: port,
          peer_pid_address_port: peer_pid_address_port
        } = state
      ) do
    Logger.debug("announcing to #{inspect(TorrentFile.announce(info_hash))}")

    {:ok, length} = TorrentFile.length(info_hash)

    %{announce_response: announce_response, additional_peer_statuses: additional_peer_statuses} =
      case Tracker.announce(info_hash, peer_id, port,
             event: "started",
             # TODO compute real "left"
             left: length,
             compact: true
           ) do
        {:ok, announce_response} ->
          announce_response =
            Map.update!(announce_response, :peers, fn peers ->
              Enum.filter(peers, fn peer ->
                if other_peer_id = Map.get(peer, :peer_id) do
                  other_peer_id != peer_id && (peer.ip != {127, 0, 0, 1} && peer.port != port)
                else
                  peer.ip != {127, 0, 0, 1} && peer.port != port
                end
              end)
            end)

          additional_peer_statuses =
            Enum.reduce(announce_response.peers, %{}, fn %{ip: ip, port: port}, acc ->
              if !BiMap.has_value?(peer_pid_address_port, {ip, port}) do
                case PeerSupervisor.start_peer_for_outgoing_connection(
                       info_hash,
                       peer_id,
                       ip,
                       port
                     ) do
                  {:ok, peer_pid} ->
                    _peer_ref = Process.monitor(peer_pid)

                    Logger.debug("successfully connected to #{inspect(ip)}:#{port}")

                    Map.put(acc, peer_pid, %{
                      interested_in_peer: false,
                      choking_peer: true,
                      peer_is_interested_in_us: false,
                      peer_is_choking_us: true
                    })

                  _ ->
                    Logger.debug("unable to connect to #{inspect(ip)}:#{port}")
                    acc
                end
              end
            end)

          Process.send_after(self(), :announce, :timer.seconds(announce_response[:interval]))

          %{
            announce_response: announce_response,
            additional_peer_statuses: additional_peer_statuses
          }

        {:error, e} = error ->
          Logger.debug("Error announcing: #{inspect(e)}")
          Process.send_after(self(), :announce, :timer.minutes(3))
          %{announce_response: error, additional_peer_statuses: %{}}
      end

    state = %{
      state
      | announce_response: announce_response,
        peer_statuses: Map.merge(state.peer_statuses, additional_peer_statuses)
    }

    {:noreply, state}
  end

  # defp get_(remaining_wanted_pieces, inflight_request_set) do
  # end

  # this would be so much better with a relational database!
  def handle_info(
        :request_tick,
        %State{
          inflight_requests: inflight_requests,
          peers_have_pieces: peers_have_pieces
        } = state
      ) do
    blocks_to_request =
      get_blocks_to_request(state)

    if Enum.empty?(blocks_to_request) do
      Logger.debug("no blocks to request")
      Process.send_after(self(), :request_tick, :timer.seconds(5))
      {:noreply, state}
    else
      Logger.debug("requesting #{Enum.count(blocks_to_request)} pieces")

      inflight_requests =
        Enum.reduce(blocks_to_request, inflight_requests, fn {piece_index, begin, length} =
                                                               request,
                                                             acc ->
          random_peer =
            peers_have_pieces
            |> BiMultiMap.get(piece_index)
            |> Enum.random()

          PeerWorker.request_block(random_peer, piece_index, begin, length)

          Logger.debug("asked peer #{inspect(random_peer)} to request piece #{piece_index}")

          BiMultiMap.put(acc, random_peer, request)
        end)

      # `peer pid` -> `{piece_index, begin, length}` (block)
      state = %{state | inflight_requests: inflight_requests}

      Process.send_after(self(), :request_tick, :timer.seconds(1))

      {:noreply, state}
    end
  end

  # TODO do something smarter here like tracking upload and download rate
  # and reciprocating to peers that allow us to leach.
  #
  # for now, just randomly choke and unchoke peers
  def handle_info(
        :unchoke_tick,
        %State{maximum_uploads: maximum_uploads, peer_statuses: peer_statuses} = state
      ) do
    peer_statuses = choke_and_unchoke_peers(peer_statuses, maximum_uploads)

    state = %{state | peer_statuses: peer_statuses}

    Process.send_after(self(), :unchoke_tick, :timer.seconds(10))

    {:noreply, state}
  end

  def handle_info(:clear_old_inflight_requests, %State{} = state) do
    state =
      if BiMultiMap.size(state.inflight_requests) > 0 do
        Logger.debug("cleared #{Enum.count(state.inflight_requests)} old requests")
        %{state | inflight_requests: BiMultiMap.new()}
      else
        Logger.debug("no old requests")
        state
      end

    Process.send_after(self(), :clear_old_inflight_requests, :timer.seconds(30))

    # TODO should we also send cancel messages to peers here or no?

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    # TODO send cancel messages to peers so they cancel their block requests
    state = %{
      state
      | peers_have_pieces: BiMultiMap.delete_value(state.peers_have_pieces, pid),
        inflight_requests: BiMultiMap.delete_key(state.inflight_requests, pid),
        peer_statuses: Map.delete(state.peer_statuses, pid),
        peer_pid_peer_id: BiMap.delete_key(state.peer_pid_peer_id, pid),
        peer_pid_address_port: BiMap.delete_key(state.peer_pid_address_port, pid)
    }

    {:noreply, state}
  end

  # TODO actually set up a separate process to monitor this process
  # and perform this cleanup there
  def terminate(_reason, %State{info_hash: info_hash}) do
    TorrentFile.delete(info_hash)
    :ok
  end

  ### PRIVATE ###

  def choke_and_unchoke_peers(peer_statuses, maximum_uploads) do
    if Enum.count(peer_statuses) <= maximum_uploads do
      Enum.reduce(peer_statuses, peer_statuses, fn
        {peer_pid, %{choking_peer: true}}, acc ->
          PeerWorker.unchoke(peer_pid)

          Map.update!(acc, peer_pid, fn peer_status ->
            %{peer_status | choking_peer: false}
          end)

        {_peer_pid, %{choking_peer: false}}, acc ->
          acc
      end)
      |> Enum.into(%{})
    else
      choked_and_unchoked_peers =
        Enum.group_by(
          peer_statuses,
          fn {_peer_pid, peer_status} ->
            if peer_status[:choking_peer] do
              :choked
            else
              :unchoked
            end
          end
        )

      choked_peers = Map.get(choked_and_unchoked_peers, :choked, [])
      unchoked_peers = Map.get(choked_and_unchoked_peers, :unchoked, [])

      peer_statuses =
        Enum.reduce(unchoked_peers, peer_statuses, fn {peer_pid, _peer_status}, acc ->
          PeerWorker.choke(peer_pid)
          put_in(acc, [peer_pid, :choking_peer], true)
        end)

      peer_statuses =
        choked_peers
        |> Enum.take(maximum_uploads)
        |> Enum.reduce(peer_statuses, fn {peer_pid, _peer_status}, acc ->
          PeerWorker.unchoke(peer_pid)
          put_in(acc, [peer_pid, :choking_peer], false)
        end)

      peer_statuses
    end
  end

  def get_blocks_to_request(%{
        info_hash: info_hash,
        # unpadded bitstring
        piece_statuses: piece_statuses,
        # mapping of `piece index` -> `peer pid`
        peers_have_pieces: peers_have_pieces,
        # mapping of `pid ->
        # %{
        #   interested_in_peer: bool,
        #   choking_peer: bool,
        #   peer_is_interested_in_us: bool,
        #   peer_is_choking_us: bool
        # }`
        peer_statuses: peer_statuses,
        # `peer_pid -> {piece_index, block_begin, block_length}`
        inflight_requests: inflight_requests,
        # integer nominal block length
        block_length: block_length,
        # the max number of active block requests to have at any given time
        inflight_requests_target: inflight_requests_target
      }) do
    all_wanted_pieces =
      piece_statuses |> get_zeroes_indexes() |> MapSet.new()

    # - get all wanted pieces
    # - work through all pieces that peers `have`
    #   to get blocks from those pieces until we get a target number of blocks
    #   or exhaust all wanted pieces
    #
    #
    # for a given wanted piece that peers have
    # get its blocks
    # if those blocks are already requests_inflight, skip
    # if not, add to list
    # repeat until we reach target number of blocks or exhaust pieces

    peers_that_arent_choking_us =
      peer_statuses
      |> Enum.filter(fn
        {_peer_pid, %{peer_is_choking_us: false}} ->
          true

        _ ->
          false
      end)
      |> Enum.map(fn {peer_pid, _peer_status} -> peer_pid end)
      |> MapSet.new()

    pieces_peers_have_in_rarity_order =
      peers_have_pieces
      # %{piece_index => [peer_pid]}
      |> Enum.filter(fn {_piece_index, peer_pid} ->
        MapSet.member?(peers_that_arent_choking_us, peer_pid)
      end)
      |> Enum.group_by(
        fn {piece_index, _peer} -> piece_index end,
        fn {_piece_index, peer} -> peer end
      )
      # %{piece_index => integer}
      |> Enum.sort_by(fn {_piece_index, peers_that_have_this_piece} ->
        Enum.count(peers_that_have_this_piece)
      end)
      # %{piece_index => integer}
      |> Enum.filter(fn {_piece_index, number_of_peers_that_have_this_piece} ->
        number_of_peers_that_have_this_piece > 0
      end)
      # [integer]
      |> Enum.map(fn {piece_index, _number_of_peers_that_have_this_piece} ->
        piece_index
      end)

    wanted_pieces_peers_have =
      pieces_peers_have_in_rarity_order
      |> Enum.filter(fn piece_index ->
        MapSet.member?(all_wanted_pieces, piece_index)
      end)

    inflight_requests_set =
      inflight_requests
      |> BiMultiMap.values()
      |> MapSet.new()

    wanted_number_of_new_blocks =
      max(0, inflight_requests_target - Enum.count(inflight_requests))

    Enum.reduce_while(wanted_pieces_peers_have, MapSet.new(), fn piece_index, acc ->
      prospective_blocks_to_request_count = Enum.count(acc)

      if prospective_blocks_to_request_count >= wanted_number_of_new_blocks do
        {:halt, acc}
      else
        wanted_blocks =
          TorrentFile.blocks_for_piece(info_hash, piece_index, block_length)
          |> Enum.map(fn {begin, length} -> {piece_index, begin, length} end)
          |> MapSet.new()
          |> MapSet.difference(inflight_requests_set)

        delta = wanted_number_of_new_blocks - prospective_blocks_to_request_count

        blocks_to_add =
          wanted_blocks
          |> Enum.sort_by(fn {_piece_index, begin, _length} -> begin end)
          |> Enum.take(delta)
          |> MapSet.new()

        {:cont, MapSet.union(acc, blocks_to_add)}
      end
    end)
  end

  def get_zeroes_indexes(bits) when is_bitstring(bits) do
    for <<bit::1 <- bits>>, reduce: {[], 0} do
      {zeroes, current_index} ->
        if bit == 0 do
          {[current_index | zeroes], current_index + 1}
        else
          {zeroes, current_index + 1}
        end
    end
    |> then(fn {zeroes, _} -> zeroes end)
  end

  defp name(info_hash) do
    {:via, Registry, {Etorrent.Registry, {__MODULE__, info_hash}}}
  end
end
