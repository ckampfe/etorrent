defprotocol Etorrent.Bencode.Encode do
  def encode(this)
end

defimpl Etorrent.Bencode.Encode, for: BitString do
  def encode(s) do
    len = byte_size(s)
    [Integer.to_string(len), ?:, s]
  end
end

defimpl Etorrent.Bencode.Encode, for: Atom do
  def encode(a) do
    a
    |> Atom.to_string()
    |> Etorrent.Bencode.Encode.BitString.encode()
  end
end

defimpl Etorrent.Bencode.Encode, for: Integer do
  def encode(i) do
    [?i, Integer.to_string(i), ?e]
  end
end

defimpl Etorrent.Bencode.Encode, for: Map do
  def encode(m) do
    encoded_dict =
      m
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {k, v} ->
        [
          Etorrent.Bencode.Encode.encode(k),
          Etorrent.Bencode.Encode.encode(v)
        ]
      end)

    [?d, encoded_dict, ?e]
  end
end

defimpl Etorrent.Bencode.Encode, for: List do
  def encode(l) do
    encoded_vs =
      Enum.map(l, fn v -> Etorrent.Bencode.Encode.encode(v) end)

    # unclear if this is necesssary, it isn't in the spec,
    # but does provide a stable ordering for roundtripping,
    # since dictionaries are ordered by their keys
    # |> Enum.sort_by(fn v -> String.length(v) end)
    # |> Enum.join("")

    # "l#{encoded_vs}e"
    [?l, encoded_vs, ?e]
  end
end

defmodule Etorrent.Bencode do
  ### PUBLIC API

  def encode(data) do
    encoded = Etorrent.Bencode.Encode.encode(data)
    {:ok, encoded}
  end

  def decode(s, options \\ [atom_keys: false]) do
    position = 0

    with {"", decoded, _position} <- visit_decode(s, position, options) do
      {:ok, decoded}
    end
  end

  ### IMPLS

  defp visit_decode(rest, position, options) do
    case rest do
      <<c::binary-size(1), _rest::binary>> = all when c in ~w(0 1 2 3 4 5 6 7 8 9) ->
        decode_string(all, position, atom_keys: false)

      <<"i", rest::binary>> ->
        decode_integer(rest, position + 1)

      <<"l", rest::binary>> ->
        decode_list(rest, [], position + 1, options)

      <<"d", rest::binary>> ->
        decode_dictionary(rest, %{}, position + 1, options)

      <<c::binary-size(1), _rest::binary>> ->
        # raise "unexpected character #{inspect(c)} at position #{position}"
        {:error, "unexpected character #{inspect(c)} at position #{position}"}
    end
  end

  defp decode_string(rest, position, options) do
    initial_length = byte_size(rest)
    {length, rest} = Integer.parse(rest)
    <<":", s::binary-size(length), rest::binary>> = rest
    remaining_length = byte_size(rest)

    if options[:atom_keys] do
      {rest, String.to_atom(s), position + (initial_length - remaining_length)}
    else
      {rest, s, position + (initial_length - remaining_length)}
    end
  end

  defp decode_integer(rest, position) do
    initial_length = byte_size(rest)
    {i, <<"e", rest::binary>>} = Integer.parse(rest)
    remaining_length = byte_size(rest)
    {rest, i, position + (initial_length - remaining_length)}
  end

  defp decode_list(rest, list, position, options) do
    case rest do
      <<"e", rest::binary>> ->
        {rest, list, position + 1}

      _ ->
        {rest, element, position} = visit_decode(rest, position, options)
        decode_list(rest, [element | list], position, options)
    end
  end

  defp decode_dictionary(rest, dictionary, position, options) do
    case rest do
      <<"e", rest::binary>> ->
        {rest, dictionary, position + 1}

      _ ->
        {rest, key, position} = decode_string(rest, position, options)
        {rest, value, position} = visit_decode(rest, position, options)
        decode_dictionary(rest, Map.put(dictionary, key, value), position, options)
    end
  end
end
