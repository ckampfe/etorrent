defmodule Etorrent.TorrentFile do
  @moduledoc """
  torrent files never change, so we can load them into persistent term storage
  and refer to them from any process
  """

  # TODO: this is set up for single-file mode only

  alias Etorrent.Bencode

  def new(torrent_file) when is_binary(torrent_file) do
    {:ok, decoded_torrent_file} = Bencode.decode(torrent_file, atom_keys: true)

    info_hash = info_hash(decoded_torrent_file)

    :persistent_term.put(lookup_name(info_hash), decoded_torrent_file)

    {:ok, info_hash}
  end

  def delete(info_hash) do
    :persistent_term.erase(lookup_name(info_hash))
  end

  def name(info_hash) do
    %{info: %{name: name}} = :persistent_term.get(lookup_name(info_hash))
    {:ok, name}
  end

  def length(info_hash) do
    %{info: %{length: length}} = :persistent_term.get(lookup_name(info_hash))
    {:ok, length}
  end

  def announce(info_hash) do
    %{announce: announce} = :persistent_term.get(lookup_name(info_hash))
    {:ok, announce}
  end

  @doc """
  "Every piece is of equal length except for the final piece, which is irregular.
  The number of pieces is thus determined by 'ceil( total length / piece size )'."
  """
  def number_of_pieces(info_hash) do
    %{info: %{length: length, "piece length": piece_length}} =
      :persistent_term.get(lookup_name(info_hash))

    number_of_pieces = ceil(length / piece_length)

    {:ok, number_of_pieces}
  end

  def piece_positions_lengths_and_hashes(info_hash) do
    %{info: %{pieces: piece_hashes, length: real_length, "piece length": nominal_piece_length}} =
      :persistent_term.get(lookup_name(info_hash))

    {out, _} =
      for <<piece_hash::binary-20 <- piece_hashes>>, reduce: {[], 0} do
        {outputs, i} ->
          position = i * nominal_piece_length

          number_of_pieces = ceil(real_length / nominal_piece_length)

          is_last_piece? = i == number_of_pieces - 1

          real_piece_length =
            if is_last_piece? do
              nominal_length = number_of_pieces * nominal_piece_length

              delta = nominal_length - real_length

              last_piece_length = nominal_piece_length - delta

              last_piece_length
            else
              nominal_piece_length
            end

          {[%{position: position, length: real_piece_length, hash: piece_hash} | outputs], i + 1}
      end

    {:ok, Enum.reverse(out)}
  end

  def blocks_for_piece(info_hash, piece_index, block_size) do
    %{info: %{length: real_length, "piece length": nominal_piece_length}} =
      :persistent_term.get(lookup_name(info_hash))

    number_of_pieces = ceil(real_length / nominal_piece_length)

    is_last_piece? = piece_index == number_of_pieces - 1

    real_piece_length =
      if is_last_piece? do
        nominal_length = number_of_pieces * nominal_piece_length

        delta = nominal_length - real_length

        last_piece_length = nominal_piece_length - delta

        last_piece_length
      else
        nominal_piece_length
      end

    chunkify(real_piece_length, block_size)
  end

  @doc """
  generically chunkify some length by some chunk size.
  always returns at least 1 chunk, which can have a length less than chunk size.
  """
  def chunkify(thing_length, chunk_size) when thing_length > 0 and chunk_size > 0 do
    number_of_chunks = ceil(thing_length / chunk_size)

    Enum.reduce(
      0..(number_of_chunks - 1),
      {[], thing_length},
      fn i, {chunks, remaining} ->
        if chunk_size <= remaining do
          {[{i * chunk_size, chunk_size} | chunks], remaining - chunk_size}
        else
          {[{i * chunk_size, remaining} | chunks], 0}
        end
      end
    )
    |> then(fn {chunks, 0} ->
      Enum.reverse(chunks)
    end)
  end

  def piece_position_length_and_hash(info_hash, i) do
    %{info: %{pieces: piece_hashes, length: real_length, "piece length": nominal_piece_length}} =
      :persistent_term.get(lookup_name(info_hash))

    position = i * nominal_piece_length

    number_of_pieces = ceil(real_length / nominal_piece_length)

    is_last_piece? = i == number_of_pieces - 1

    real_piece_length =
      if is_last_piece? do
        nominal_length = number_of_pieces * nominal_piece_length

        delta = nominal_length - real_length

        last_piece_length = nominal_piece_length - delta

        last_piece_length
      else
        nominal_piece_length
      end

    <<_prefix::binary-size(i * 20), hash::binary-20, _rest::binary>> =
      piece_hashes

    {:ok, %{position: position, length: real_piece_length, hash: hash}}
  end

  def nominal_piece_length(info_hash) do
    %{info: %{"piece length": nominal_piece_length}} =
      :persistent_term.get(lookup_name(info_hash))

    {:ok, nominal_piece_length}
  end

  defp info_hash(%{info: info}) do
    info
    |> Bencode.encode()
    |> then(fn {:ok, encoded} ->
      bin = :erlang.iolist_to_binary(encoded)
      :crypto.hash(:sha, bin)
    end)
  end

  defp lookup_name(info_hash) do
    {__MODULE__, info_hash}
  end
end
