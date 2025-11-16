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

  test "verify_all_pieces/2", %{info_hash: info_hash, data_file: data_file} do
    assert {:ok, bits} = DataFile.verify_all_pieces(info_hash, data_file)
    assert bit_size(bits) == 30

    for <<bit::1 <- bits>> do
      assert bit == 1
    end
  end

  test "verify_piece/2", %{info_hash: info_hash, data_file: data_file} do
    {:ok, number_of_pieces} = TorrentFile.number_of_pieces(info_hash)

    Enum.each(0..(number_of_pieces - 1), fn i ->
      assert {:ok, true} = DataFile.verify_piece(info_hash, data_file, i)
    end)
  end

  test "set_bit/2" do
    assert <<1::1, 0::1, 0::1>> = DataFile.set_bit(<<0::1, 0::1, 0::1>>, 0)
    assert <<0::1, 1::1, 0::1>> = DataFile.set_bit(<<0::1, 0::1, 0::1>>, 1)
    assert <<0::1, 0::1, 1::1>> = DataFile.set_bit(<<0::1, 0::1, 0::1>>, 2)
  end

  test "pad_to_full_octets/1" do
    assert <<>> == DataFile.pad_to_full_octets(<<>>)

    assert <<1::8>> == DataFile.pad_to_full_octets(<<1::8>>)

    assert <<1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>> ==
             DataFile.pad_to_full_octets(<<1::1>>)

    assert <<255, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>> ==
             DataFile.pad_to_full_octets(<<255, 4::3>>)

    assert <<255, 255, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>> ==
             DataFile.pad_to_full_octets(<<255, 255, 4::3>>)
  end
end
