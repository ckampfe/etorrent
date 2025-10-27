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

  defmodule PieceHashes do
    defstruct [:piece_hashes, :nominal_piece_length, :last_piece_length]

    def new(%{
          pieces: pieces,
          length: data_length,
          "piece length": nominal_piece_length
        }) do
      piece_hashes =
        for <<hash::binary-20 <- pieces>> do
          hash
        end

      delta =
        length(piece_hashes) * nominal_piece_length - data_length

      last_piece_length =
        nominal_piece_length - delta

      %__MODULE__{
        piece_hashes: piece_hashes,
        nominal_piece_length: nominal_piece_length,
        last_piece_length: last_piece_length
      }
    end

    # TODO parallelize this
    def verify_pieces(self, file) do
      len = count(self)

      Enum.reduce(0..(len - 1), [], fn i, acc ->
        [verify_piece(self, i, file) | acc]
      end)
      |> Enum.reverse()
    end

    def verify_piece(self, i, file) do
      position = piece_position(self, i)

      %{hash: expected_hash, length: length} = get_piece_hash_and_length(self, i)

      with {:ok, piece_on_disk} <- :file.pread(file, position, length) do
        :crypto.hash(:sha, piece_on_disk) == expected_hash
      end
    end

    def piece_position(%__MODULE__{} = self, i) do
      i * self.nominal_piece_length
    end

    def count(%__MODULE__{piece_hashes: piece_hashes}) do
      Kernel.length(piece_hashes)
    end

    def get_piece_hash_and_length(%__MODULE__{} = self, i) do
      hash = Enum.at(self.piece_hashes, i)

      length =
        if i == length(self.piece_hashes) - 1 do
          self.last_piece_length
        else
          self.nominal_piece_length
        end

      %{
        hash: hash,
        length: length
      }
    end
  end
end
