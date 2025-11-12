defmodule Etorrent.TorrentWorkerTest do
  use ExUnit.Case
  alias Etorrent.{TorrentFile, TorrentWorker}

  setup do
    f = File.read!("doomguy.png.torrent")
    {:ok, info_hash} = TorrentFile.new(f)

    on_exit(fn ->
      TorrentFile.delete(info_hash)
    end)

    %{info_hash: info_hash}
  end

  test "get_zeroes_indexes/1" do
    assert [] == TorrentWorker.get_zeroes_indexes(<<>>)
    assert [] == TorrentWorker.get_zeroes_indexes(<<1::1, 1::1, 1::1, 1::1, 1::1>>)
    assert [2, 1] == TorrentWorker.get_zeroes_indexes(<<1::1, 0::1, 0::1, 1::1, 1::1>>)
    assert [4, 3, 2, 1, 0] == TorrentWorker.get_zeroes_indexes(<<0::1, 0::1, 0::1, 0::1, 0::1>>)
  end

  describe "get_blocks_to_request/1" do
    test "returns no blocks if we have all pieces", %{info_hash: info_hash} do
      assert MapSet.new([]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<1::1, 1::1, 1::1, 1::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests: BiMultiMap.new(),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "returns blocks only for the piece we don't have", %{info_hash: info_hash} do
      assert MapSet.new([{3, 0, 16384}, {3, 16384, 16384}]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<1::1, 1::1, 1::1, 0::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests: BiMultiMap.new(),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "does not return blocks for pieces peers don't have", %{info_hash: info_hash} do
      assert MapSet.new([]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<1::1, 0::1, 1::1, 1::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests: BiMultiMap.new(),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "respects given block_length", %{info_hash: info_hash} do
      block_length = 10000

      assert MapSet.new([{3, 0, 10000}, {3, 10000, 10000}, {3, 20000, 10000}, {3, 30000, 2768}]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<1::1, 1::1, 1::1, 0::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests: BiMultiMap.new(),
                 # integer nominal block length
                 block_length: block_length,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "with no inflight requests", %{info_hash: info_hash} do
      assert MapSet.new([
               {0, 0, 16384},
               {0, 16384, 16384},
               {2, 0, 16384},
               {2, 16384, 16384}
             ]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<0::1, 0::1, 0::1, 1::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests: BiMultiMap.new(),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "does not include inflight requests", %{info_hash: info_hash} do
      assert MapSet.new([
               {0, 16384, 16384},
               {2, 16384, 16384}
             ]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<0::1, 0::1, 0::1, 1::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests:
                   BiMultiMap.new(%{
                     :some_pid => {0, 0, 16384},
                     :some_other_pid => {2, 0, 16384}
                   }),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "keeps the number of requests <= inflight_requests_target", %{info_hash: info_hash} do
      assert MapSet.new([{2, 16384, 16384}]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<0::1, 0::1, 0::1, 1::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests:
                   BiMultiMap.new(%{
                     :some_pid => {0, 0, 16384},
                     :some_other_pid => {2, 0, 16384}
                   }),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 3,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })

      assert MapSet.new([]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<0::1, 0::1, 0::1, 1::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests:
                   BiMultiMap.new(%{
                     :some_pid => {0, 0, 16384},
                     :some_other_pid => {2, 0, 16384},
                     :some_other_other_pid => {2, 16384, 16384}
                   }),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 3,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: false},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end

    test "only offers blocks from peers that aren't choking us", %{info_hash: info_hash} do
      # peer ":b" is choking us,
      # peers ":a" and ":c" are not choking us
      assert MapSet.new([{0, 0, 16384}, {0, 16384, 16384}, {2, 0, 16384}, {2, 16384, 16384}]) ==
               TorrentWorker.get_blocks_to_request(%{
                 info_hash: info_hash,
                 # unpadded bitstring
                 piece_statuses: <<0::1, 1::1, 0::1, 0::1, 1::1>>,
                 # mapping of `piece index` -> `peer pid`
                 peers_have_pieces:
                   BiMultiMap.new([
                     {0, :a},
                     {0, :b},
                     {0, :c},
                     {2, :a},
                     {2, :c},
                     {3, :b},
                     {4, :a},
                     {4, :b},
                     {4, :c}
                   ]),
                 # `peer_pid -> {piece_index, block_begin, block_length}`
                 inflight_requests: BiMultiMap.new(),
                 # integer nominal block length
                 block_length: 2 ** 14,
                 # the max number of active block requests to have at any given time
                 inflight_requests_target: 10,
                 peer_statuses: %{
                   a: %{peer_is_choking_us: false},
                   b: %{peer_is_choking_us: true},
                   c: %{peer_is_choking_us: false}
                 }
               })
    end
  end
end
