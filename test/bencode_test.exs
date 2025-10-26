defmodule Etorrent.BencodeTest do
  use ExUnit.Case
  alias Etorrent.Bencode

  test "roundtrips" do
    f = File.read!("doomguy.png.torrent")
    {:ok, decoded} = Bencode.decode(f, atom_keys: true)
    {:ok, encoded} = Bencode.encode(decoded)
    encoded_bin = :erlang.iolist_to_binary(encoded)

    assert encoded_bin == f

    info_hash =
      decoded
      |> Etorrent.info_hash()
      |> Base.encode16(case: :lower)

    # from Transmission 4.0.6
    assert info_hash == "0b925b010556940a91ed5ed5a7f52f4ff209ec65"
  end
end
