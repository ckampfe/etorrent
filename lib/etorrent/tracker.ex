defmodule Etorrent.Tracker do
  alias Etorrent.Bencode

  def announce(torrent_file, peer_id, port, options \\ [compact: false]) do
    info_hash = Etorrent.info_hash(torrent_file)

    url =
      torrent_file[:announce]
      |> URI.parse()
      |> URI.append_query("info_hash=#{URI.encode(info_hash, &URI.char_unreserved?/1)}")
      |> URI.append_query("peer_id=#{URI.encode(peer_id, &URI.char_unreserved?/1)}")
      |> URI.append_query("port=#{port}")
      |> URI.append_query("uploaded=0")
      |> URI.append_query("downloaded=0")

    url =
      if options[:left] do
        URI.append_query(url, "left=#{options[:left]}")
      else
        url
      end

    url =
      if options[:event] do
        URI.append_query(url, "event=#{options[:event]}")
      else
        url
      end

    response =
      Req.get(url)

    case response do
      {:ok, response} ->
        case response.status do
          200 ->
            {:ok, decoded_tracker_response} =
              Bencode.decode(response.body, atom_keys: true)

            if failure_reason = Map.get(decoded_tracker_response, :failure_reason) do
              {:error, failure_reason}
            else
              out =
                if options[:compact] do
                  decoded_tracker_response
                else
                  un_utf8_peer_ids(decoded_tracker_response)
                end

              {:ok, out}
            end

          _status ->
            with {:ok, decoded_error} <- Bencode.decode(response.body, atom_keys: true) do
              {:error, decoded_error}
            else
              _ ->
                {:error, response.body}
            end
        end

      {:error, _e} = error ->
        error
    end
  end

  defp un_utf8_peer_ids(decoded_tracker_response) do
    Map.update!(decoded_tracker_response, :peers, fn peers ->
      Enum.reduce(peers, [], fn peer, acc ->
        updated_peer =
          Map.update!(peer, :"peer id", fn
            peer_id when is_binary(peer_id) ->
              # needed to turn UTF-8 respones from `bittorrent-tracker` in
              peer_id |> String.to_charlist() |> :binary.list_to_bin()

            peer_id ->
              peer_id
          end)

        [updated_peer | acc]
      end)
    end)
  end
end
