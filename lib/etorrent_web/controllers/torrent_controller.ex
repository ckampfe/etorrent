defmodule EtorrentWeb.TorrentController do
  use EtorrentWeb, :controller

  def index(conn, params) do
    torrents = Etorrent.get_all_torrent_metrics()

    add_torrent = Map.get(params, "add_torrent", false)

    render(conn, :index,
      torrents: torrents,
      torrent_changeset: Phoenix.Component.to_form(%{}),
      add_torrent: add_torrent
    )
  end

  def create(
        conn,
        %{"torrent_file" => torrent_file, "data_path" => dangerous_data_path} = _params
      ) do
    {:ok, _} = File.stat(dangerous_data_path)

    torrent_binary = File.read!(torrent_file.path)

    Etorrent.new_torrent(torrent_binary, dangerous_data_path)

    conn
    |> redirect(to: ~p"/")
  end

  def show(conn, %{"info_hash" => info_hash_hex} = _params) do
    info_hash = Base.decode16!(info_hash_hex)

    {:ok, torrent} = Etorrent.get_torrent_metrics(info_hash)

    side_length = make_square_from_list(length(torrent[:pieces]))

    conn
    |> render(:show, torrent: torrent, side_length: side_length)
  end

  def make_square_from_list(i) do
    i |> :math.sqrt() |> ceil()
  end
end
