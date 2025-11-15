defmodule Etorrent.Tracker do
  alias Etorrent.{Bencode, TorrentFile}

  def announce(info_hash, peer_id, port, options \\ [compact: false]) do
    {:ok, announce_url} = TorrentFile.announce(info_hash)

    url =
      announce_url
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

    url =
      if options[:compact] do
        URI.append_query(url, "compact=1")
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
              {:ok, normalize_response(decoded_tracker_response)}
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

  def normalize_response(decoded_tracker_response) do
    case decoded_tracker_response do
      %{peers: peers} when is_binary(peers) ->
        # from bencode:
        #
        #  %{
        #    complete: 0,
        #    incomplete: 1,
        #    interval: 600,
        #    peers: <<127, 0, 0, 1, 35, 40>>,
        #    peers6: ""
        #  }
        ipv4_peers =
          for <<a1, a2, a3, a4, port::unsigned-integer-16 <- peers>> do
            %{ip: {a1, a2, a3, a4}, port: port}
          end

        peers6 = Map.get(decoded_tracker_response, :peers6, "")

        ipv6_peers =
          for <<a1::16, a2::16, a3::16, a4::16, a5::16, a6::16, a7::16, a8::16,
                port::unsigned-integer-16 <- peers6>> do
            %{ip: {a1, a2, a3, a4, a5, a6, a7, a8}, port: port}
          end

        decoded_tracker_response
        |> Map.put(:peers, ipv4_peers ++ ipv6_peers)
        |> Map.delete(:peers6)

      %{peers: peers} when is_list(peers) ->
        # from bencode:
        #
        #  %{
        #    complete: 0,
        #    incomplete: 1,
        #    interval: 600,
        #    peers: [%{port: 9000, ip: "127.0.0.1", "peer id": "-ET0001-776484494511"}]
        #  }
        Map.put(
          decoded_tracker_response,
          :peers,
          Enum.map(peers, fn %{"peer id": peer_id} = peer ->
            peer_id = peer_id |> String.to_charlist() |> :binary.list_to_bin()

            peer
            |> Map.put(:peer_id, peer_id)
            |> Map.delete(:"peer id")
            |> Map.update!(:ip, fn ip ->
              {:ok, ip} =
                ip
                |> to_charlist
                |> :inet.parse_address()

              ip
            end)
          end)
        )
    end
  end
end
