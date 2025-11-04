defmodule Etorrent.TorrentFileTest do
  use ExUnit.Case
  alias Etorrent.TorrentFile

  setup do
    f = File.read!("doomguy.png.torrent")
    {:ok, info_hash} = TorrentFile.new(f)

    on_exit(fn ->
      TorrentFile.delete(info_hash)
    end)

    %{info_hash: info_hash}
  end

  test "name/1", %{info_hash: info_hash} do
    assert {:ok, "a8dmfmt66t211.png"} = TorrentFile.name(info_hash)
  end

  test "length/1", %{info_hash: info_hash} do
    assert {:ok, 978_864} = TorrentFile.length(info_hash)
  end

  test "announce/1", %{info_hash: info_hash} do
    assert {:ok, "http://localhost:8000/announce"} = TorrentFile.announce(info_hash)
  end

  test "number_of_pieces/1", %{info_hash: info_hash} do
    assert {:ok, 30} = TorrentFile.number_of_pieces(info_hash)
  end

  test "piece_positions_lengths_and_hashes/1", %{info_hash: info_hash} do
    assert {:ok,
            [
              %{
                position: 0,
                length: 32768,
                hash:
                  <<211, 72, 98, 164, 227, 72, 156, 255, 43, 123, 46, 235, 176, 164, 227, 145,
                    210, 218, 98, 222>>
              },
              %{
                position: 32768,
                length: 32768,
                hash:
                  <<141, 25, 2, 67, 10, 248, 191, 238, 47, 146, 225, 36, 51, 69, 102, 4, 222, 222,
                    62, 249>>
              },
              %{
                position: 65536,
                length: 32768,
                hash:
                  <<146, 187, 149, 185, 159, 183, 136, 191, 245, 65, 3, 94, 127, 46, 244, 46, 95,
                    53, 91, 96>>
              },
              %{
                position: 98304,
                length: 32768,
                hash:
                  <<234, 102, 120, 71, 99, 139, 13, 108, 194, 4, 32, 117, 33, 128, 162, 34, 108,
                    99, 192, 96>>
              },
              %{
                position: 131_072,
                length: 32768,
                hash:
                  <<139, 174, 99, 136, 109, 67, 234, 80, 119, 35, 255, 115, 126, 94, 204, 249, 31,
                    70, 72, 127>>
              },
              %{
                position: 163_840,
                length: 32768,
                hash:
                  <<29, 242, 193, 124, 56, 99, 197, 39, 161, 119, 3, 169, 164, 241, 49, 205, 225,
                    9, 94, 0>>
              },
              %{
                position: 196_608,
                length: 32768,
                hash:
                  <<217, 70, 75, 246, 174, 227, 127, 36, 49, 170, 179, 50, 62, 238, 96, 63, 247,
                    141, 136, 220>>
              },
              %{
                position: 229_376,
                length: 32768,
                hash:
                  <<202, 223, 151, 72, 227, 190, 228, 198, 28, 162, 234, 43, 171, 191, 255, 20,
                    124, 171, 114, 2>>
              },
              %{
                position: 262_144,
                length: 32768,
                hash:
                  <<244, 218, 92, 128, 53, 55, 220, 177, 126, 81, 156, 197, 177, 91, 68, 2, 73,
                    29, 151, 255>>
              },
              %{
                position: 294_912,
                length: 32768,
                hash:
                  <<82, 53, 64, 130, 86, 85, 167, 219, 243, 247, 77, 18, 109, 40, 123, 96, 165,
                    30, 249, 68>>
              },
              %{
                position: 327_680,
                length: 32768,
                hash:
                  <<251, 180, 186, 36, 199, 157, 29, 101, 18, 34, 66, 194, 46, 157, 237, 122, 125,
                    77, 113, 85>>
              },
              %{
                position: 360_448,
                length: 32768,
                hash:
                  <<16, 170, 131, 76, 60, 186, 141, 156, 205, 120, 248, 108, 124, 24, 155, 200,
                    30, 47, 224, 22>>
              },
              %{
                position: 393_216,
                length: 32768,
                hash:
                  <<152, 127, 36, 4, 22, 176, 79, 128, 185, 32, 209, 49, 198, 66, 54, 43, 75, 172,
                    132, 90>>
              },
              %{
                position: 425_984,
                length: 32768,
                hash:
                  <<242, 120, 5, 204, 101, 210, 131, 45, 225, 91, 180, 85, 218, 40, 237, 135, 71,
                    115, 123, 139>>
              },
              %{
                position: 458_752,
                length: 32768,
                hash:
                  <<162, 45, 21, 218, 195, 23, 113, 56, 153, 84, 3, 124, 198, 58, 34, 136, 131,
                    62, 127, 108>>
              },
              %{
                position: 491_520,
                length: 32768,
                hash:
                  <<144, 109, 39, 254, 173, 142, 204, 236, 221, 97, 208, 117, 40, 236, 201, 59, 6,
                    104, 247, 116>>
              },
              %{
                position: 524_288,
                length: 32768,
                hash:
                  <<83, 228, 3, 120, 131, 203, 159, 14, 113, 67, 145, 229, 113, 205, 134, 225,
                    255, 182, 161, 157>>
              },
              %{
                position: 557_056,
                length: 32768,
                hash:
                  <<234, 180, 201, 87, 4, 167, 214, 231, 72, 31, 8, 197, 181, 216, 15, 118, 55,
                    50, 236, 216>>
              },
              %{
                position: 589_824,
                length: 32768,
                hash:
                  <<175, 136, 127, 153, 237, 189, 12, 35, 189, 89, 60, 216, 247, 120, 0, 153, 12,
                    2, 98, 103>>
              },
              %{
                position: 622_592,
                length: 32768,
                hash:
                  <<214, 1, 105, 100, 104, 53, 215, 145, 27, 69, 218, 236, 115, 52, 126, 104, 193,
                    41, 115, 229>>
              },
              %{
                position: 655_360,
                length: 32768,
                hash:
                  <<107, 72, 150, 211, 108, 157, 21, 175, 153, 167, 170, 22, 195, 9, 193, 31, 168,
                    157, 112, 231>>
              },
              %{
                position: 688_128,
                length: 32768,
                hash:
                  <<66, 211, 62, 33, 77, 138, 70, 80, 252, 137, 69, 60, 154, 163, 32, 114, 60,
                    167, 5, 2>>
              },
              %{
                position: 720_896,
                length: 32768,
                hash:
                  <<98, 8, 11, 159, 213, 98, 126, 29, 0, 171, 175, 1, 138, 84, 93, 93, 39, 53, 76,
                    31>>
              },
              %{
                position: 753_664,
                length: 32768,
                hash:
                  <<32, 212, 241, 240, 213, 133, 172, 40, 85, 153, 122, 30, 62, 128, 70, 182, 198,
                    226, 145, 109>>
              },
              %{
                position: 786_432,
                length: 32768,
                hash:
                  <<200, 175, 168, 101, 50, 117, 200, 127, 87, 123, 229, 202, 208, 175, 0, 223,
                    174, 143, 37, 48>>
              },
              %{
                position: 819_200,
                length: 32768,
                hash:
                  <<128, 105, 246, 143, 100, 148, 185, 51, 243, 225, 175, 215, 246, 176, 120, 10,
                    95, 116, 90, 50>>
              },
              %{
                position: 851_968,
                length: 32768,
                hash:
                  <<3, 181, 121, 226, 119, 162, 126, 161, 255, 218, 160, 84, 100, 240, 34, 208,
                    224, 124, 160, 252>>
              },
              %{
                position: 884_736,
                length: 32768,
                hash:
                  <<215, 100, 240, 191, 137, 155, 111, 55, 170, 25, 221, 234, 82, 212, 1, 42, 192,
                    48, 46, 23>>
              },
              %{
                position: 917_504,
                length: 32768,
                hash:
                  <<207, 57, 211, 88, 7, 170, 53, 125, 94, 224, 225, 123, 237, 49, 182, 142, 37,
                    219, 124, 53>>
              },
              %{
                position: 950_272,
                length: 28592,
                hash:
                  <<137, 61, 129, 72, 24, 232, 59, 53, 227, 87, 172, 139, 245, 45, 115, 198, 73,
                    44, 197, 23>>
              }
            ]} =
             TorrentFile.piece_positions_lengths_and_hashes(info_hash)
  end

  test "piece_position_length_and_hash/2", %{info_hash: info_hash} do
    {:ok, all} = TorrentFile.piece_positions_lengths_and_hashes(info_hash)
    {:ok, number_of_pieces} = TorrentFile.number_of_pieces(info_hash)

    Enum.each(0..(number_of_pieces - 1), fn i ->
      {:ok, position_length_and_hash} = TorrentFile.piece_position_length_and_hash(info_hash, i)
      assert position_length_and_hash == Enum.at(all, i)
    end)
  end

  test "chunkify/2" do
    assert [{0, 50}, {50, 50}] = TorrentFile.chunkify(100, 50)
    assert [{0, 50}, {50, 50}, {100, 1}] = TorrentFile.chunkify(101, 50)
    assert [{0, 20}] = TorrentFile.chunkify(20, 50)
    assert [{0, 1}, {1, 1}, {2, 1}, {3, 1}, {4, 1}] = TorrentFile.chunkify(5, 1)
  end
end
