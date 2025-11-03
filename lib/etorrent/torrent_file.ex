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

  # def last_piece_length(info_hash) do
  #   %{info: %{length: real_length, "piece length": piece_length}} =
  #     :persistent_term.get(lookup_name(info_hash))

  #   number_of_pieces = ceil(real_length / piece_length)

  #   nominal_length = number_of_pieces * piece_length

  #   delta = nominal_length - real_length

  #   last_piece_length = piece_length - delta

  #   {:ok, last_piece_length}
  # end

  # def length_of_piece(info_hash, i) do
  #   %{info: %{length: real_length, "piece length": nominal_piece_length}} =
  #     :persistent_term.get(lookup_name(info_hash))

  #   number_of_pieces = ceil(real_length / nominal_piece_length)

  #   is_last_piece? = i == number_of_pieces - 1

  #   real_piece_length =
  #     if is_last_piece? do
  #       nominal_length = number_of_pieces * nominal_piece_length

  #       delta = nominal_length - real_length

  #       last_piece_length = nominal_piece_length - delta

  #       last_piece_length
  #     else
  #       nominal_piece_length
  #     end

  #   {:ok, real_piece_length}
  # end

  # def piece_hash(info_hash, piece_index) do
  #   %{info: %{pieces: piece_hashes}} = :persistent_term.get(lookup_name(info_hash))
  #   bytes_to_skip = piece_index * 20
  #   <<_skipped::binary-size(bytes_to_skip), piece_hash::binary-20, _rest::binary>> = piece_hashes
  #   {:ok, piece_hash}
  # end

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
