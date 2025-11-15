defmodule Etorrent.TrackerTest do
  use ExUnit.Case
  alias Etorrent.Tracker

  # setup do
  #   f = File.read!("doomguy.png.torrent")
  #   {:ok, info_hash} = TorrentFile.new(f)

  #   on_exit(fn ->
  #     TorrentFile.delete(info_hash)
  #   end)

  #   %{info_hash: info_hash}
  # end

  describe "normalize/1" do
    test "verbose peers" do
      assert %{
               complete: 0,
               incomplete: 1,
               interval: 600,
               peers: [%{port: 9000, ip: {127, 0, 0, 1}, peer_id: "abcdefghijklmnopqrst"}]
             } =
               Tracker.normalize_response(%{
                 complete: 0,
                 incomplete: 1,
                 interval: 600,
                 peers: [%{ip: "127.0.0.1", port: 9000, "peer id": "abcdefghijklmnopqrst"}]
               })
    end

    test "compact peers only ipv4" do
      assert %{
               complete: 0,
               incomplete: 1,
               interval: 600,
               peers: [%{port: 9000, ip: {127, 0, 0, 1}}]
             } =
               Tracker.normalize_response(%{
                 complete: 0,
                 incomplete: 1,
                 interval: 600,
                 peers: <<127, 0, 0, 1, 35, 40>>,
                 peers6: ""
               })
    end

    test "compact peers ipv4 and ipv6" do
      assert %{
               complete: 0,
               incomplete: 1,
               interval: 600,
               peers: [
                 %{port: 9000, ip: {127, 0, 0, 1}},
                 %{port: 9000, ip: {0, 0, 0, 0, 0, 0, 0, 1}}
               ]
             } =
               Tracker.normalize_response(%{
                 complete: 0,
                 incomplete: 1,
                 interval: 600,
                 peers: <<127, 0, 0, 1, 35, 40>>,
                 peers6: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 35, 40>>
               })
    end
  end
end
