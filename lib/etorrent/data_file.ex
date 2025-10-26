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

  def open_or_create(path, size \\ nil, options \\ [:read, :write, :raw]) do
    if File.exists?(path) do
      :file.open(path, options)
    else
      with {:ok, file} <- :file.open(path, options),
           {:ok, _} <- :file.position(file, size),
           :ok <- :file.truncate(file) do
        {:ok, file}
      end
    end
  end

  # file should be an opaque handle, to allow the
  # use of ram files for testing
  def write_block(file, piece_length, %Piece{index: index, begin: offset, block: block}) do
    position = index * piece_length + offset
    :file.pwrite(file, position, block)
  end

  def verify_piece(file, index, piece_length, expected_hash) do
    position = index * piece_length

    {:ok, file_info} = :file.read_file_info(file)

    real_piece_length =
      if position + piece_length > file_info.size do
        file_info.size - position
      else
        piece_length
      end

    with {:ok, piece} <- :file.pread(file, position, real_piece_length) do
      :crypto.hash(:sha, piece) == expected_hash
    end
  end
end
