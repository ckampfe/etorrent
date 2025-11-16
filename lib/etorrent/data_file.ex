defmodule Etorrent.DataFile do
  @moduledoc """
  from: https://wiki.theory.org/BitTorrentSpecification

  piece v/s block:
  In this document, a piece refers to a portion
  of the downloaded data that is described in the
  metainfo file, which can be verified by a SHA1 hash.
  A block is a portion of data that a client
  may request from a peer.
  Two or more blocks make up a whole piece, which may then be
  verified.
  """

  alias Etorrent.PeerProtocol.Piece
  alias Etorrent.TorrentFile

  def open_or_create(path, size \\ nil, options \\ [:read, :write, :binary, :raw]) do
    if File.exists?(path) do
      :file.open(path, options)
    else
      dbg(size)

      with {_, {:ok, file}} <- {:open, :file.open(path, options)},
           :ok <- :file.allocate(file, 0, size) do
        {:ok, file}
      end
    end
  end

  # file should be an opaque handle, to allow the
  # use of ram files for testing
  def write_block(info_hash, file, %Piece{index: index, begin: offset, block: block}) do
    {:ok, nominal_piece_length} = TorrentFile.nominal_piece_length(info_hash)

    position = index * nominal_piece_length + offset

    :file.pwrite(file, position, block)
  end

  def verify_all_pieces(info_hash, data_file) do
    {:ok, number_of_pieces} = TorrentFile.number_of_pieces(info_hash)

    {:ok, piece_positions_and_lengths} = TorrentFile.piece_positions_lengths_and_hashes(info_hash)

    bitfield = <<0::size(number_of_pieces)>>

    # TODO: parallelize
    out =
      piece_positions_and_lengths
      |> Enum.with_index()
      |> Enum.reduce_while(bitfield, fn {%{
                                           position: position,
                                           length: length,
                                           hash: expected_hash
                                         }, i},
                                        acc ->
        case :file.pread(data_file, position, length) do
          {:ok, piece} ->
            if :crypto.hash(:sha, piece) == expected_hash do
              acc = set_bit(acc, i)
              {:cont, acc}
            else
              {:cont, acc}
            end

          {:error, e} ->
            {:halt, {:error, e, i}}
        end
      end)

    case out do
      {:error, _e, _i} = error -> error
      _ -> {:ok, out}
    end
  end

  def send_piece(info_hash, data_file, piece_index, begin, block_length, socket) do
    with {:ok, %{position: piece_position, length: _length, hash: _expected_hash}} <-
           TorrentFile.piece_position_length_and_hash(info_hash, piece_index),
         block_position = piece_position + begin,
         {:ok, ^block_length} <-
           :file.sendfile(data_file, socket, block_position, block_length, []) do
      :ok
    end
  end

  def verify_piece(info_hash, data_file, i) do
    with {:ok, %{position: position, length: length, hash: expected_hash}} <-
           TorrentFile.piece_position_length_and_hash(info_hash, i),
         {:ok, piece} <- :file.pread(data_file, position, length) do
      {:ok, :crypto.hash(:sha, piece) == expected_hash}
    end
  end

  def set_bit(b, i) when is_bitstring(b) do
    <<prefix::bits-size(i), _this::bits-1, rest::bits>> = b
    <<prefix::bits, 1::1, rest::bits>>
  end
end
