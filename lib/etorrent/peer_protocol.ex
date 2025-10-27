defmodule Etorrent.PeerProtocol do
  defmodule Choke do
    defstruct []
  end

  defmodule Unchoke do
    defstruct []
  end

  defmodule Interested do
    defstruct []
  end

  defmodule NotInterested do
    defstruct []
  end

  defmodule Have do
    defstruct [:index]
  end

  defmodule Bitfield do
    defstruct [:bitfield]
  end

  defmodule Request do
    defstruct [:index, :begin, :length]
  end

  defmodule Piece do
    defstruct [:index, :begin, :block]
  end

  defmodule Cancel do
    defstruct [:index, :begin, :length]
  end

  defmodule Handshake do
    defstruct [:info_hash, :peer_id]
  end

  def encode_handshake(info_hash, peer_id) do
    [
      <<19>>,
      <<"BitTorrent protocol">>,
      <<0, 0, 0, 0, 0, 0, 0, 0>>,
      info_hash,
      peer_id
    ]
  end

  def decode_handshake(
        <<19, "BitTorrent protocol", _reserved::binary-size(8), info_hash::binary-size(20),
          peer_id::binary-size(20)>>
      ) do
    {:ok, %Handshake{info_hash: info_hash, peer_id: peer_id}}
  end

  def encode(m) do
    case m do
      %Choke{} ->
        <<0, 0, 0, 1, 0>>

      %Unchoke{} ->
        <<0, 0, 0, 1, 1>>

      %Interested{} ->
        <<0, 0, 0, 1, 2>>

      %NotInterested{} ->
        <<0, 0, 0, 1, 3>>

      %Have{index: index} ->
        [:binary.encode_unsigned(5), <<4>>, :binary.encode_unsigned(index)]

      %Bitfield{bitfield: bitfield} ->
        [:binary.encode_unsigned(1 + byte_size(bitfield)), <<5>>, bitfield]

      %Request{index: index, begin: begin, length: length} ->
        [
          <<0, 0, 0, 13, 6>>,
          :binary.encode_unsigned(index),
          :binary.encode_unsigned(begin),
          :binary.encode_unsigned(length)
        ]

      %Piece{index: index, begin: begin, block: block} ->
        length = 9 + byte_size(block)

        [
          :binary.encode_unsigned(length),
          <<7>>,
          :binary.encode_unsigned(index),
          :binary.encode_unsigned(begin),
          block
        ]

      %Cancel{index: index, begin: begin, length: length} ->
        [
          <<0, 0, 0, 13, 8>>,
          :binary.encode_unsigned(index),
          :binary.encode_unsigned(begin),
          :binary.encode_unsigned(length)
        ]
    end
  end

  def decode(bytes) do
    case bytes do
      <<0>> ->
        {:ok, %Choke{}}

      <<1>> ->
        {:ok, %Unchoke{}}

      <<2>> ->
        {:ok, %Interested{}}

      <<3>> ->
        {:ok, %NotInterested{}}

      <<4, index::big-integer-32>> ->
        {:ok, %Have{index: index}}

      <<5, bitfield>> ->
        {:ok, %Bitfield{bitfield: bitfield}}

      <<6, index::big-integer-32, begin::big-integer-32, length::big-integer-32>> ->
        {:ok, %Request{index: index, begin: begin, length: length}}

      <<7, index::big-integer-32, begin::big-integer-32, block::binary>> ->
        {:ok, %Piece{index: index, begin: begin, block: block}}

      <<8, index::big-integer-32, begin::big-integer-32, length::big-integer-32>> ->
        {:ok, %Cancel{index: index, begin: begin, length: length}}

      <<19, "BitTorrent protocol", _reserved::binary-size(8), info_hash::binary-size(20),
        peer_id::binary-size(20)>> ->
        {:ok, %Handshake{info_hash: info_hash, peer_id: peer_id}}

      data ->
        {:error, :unknown_data, data}
    end
  end
end
