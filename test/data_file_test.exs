defmodule Etorrent.DataFileTest do
  use ExUnit.Case
  alias Etorrent.{DataFile, TorrentFile}

  setup do
    f = File.read!("doomguy.png.torrent")

    {:ok, info_hash} = TorrentFile.new(f)

    {:ok, data_file} = DataFile.open_or_create("a8dmfmt66t211.png", [:read, :binary, :raw])

    on_exit(fn ->
      TorrentFile.delete(info_hash)
    end)

    %{info_hash: info_hash, data_file: data_file}
  end

  test "verify_pieces/2", %{info_hash: info_hash, data_file: data_file} do
    assert {:ok, bits} = DataFile.verify_pieces(info_hash, data_file)
    assert bit_size(bits) == 30

    for <<bit::1 <- bits>> do
      assert bit == 1
    end
  end

  test "set_bit/2" do
    assert <<1::1, 0::1, 0::1>> = DataFile.set_bit(<<0::1, 0::1, 0::1>>, 0)
    assert <<0::1, 1::1, 0::1>> = DataFile.set_bit(<<0::1, 0::1, 0::1>>, 1)
    assert <<0::1, 0::1, 1::1>> = DataFile.set_bit(<<0::1, 0::1, 0::1>>, 2)
  end
end
