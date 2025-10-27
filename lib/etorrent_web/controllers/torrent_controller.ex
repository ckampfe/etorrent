defmodule EtorrentWeb.TorrentController do
  use EtorrentWeb, :controller

  alias Etorrent.Bencode

  def index(conn, _params) do
    torrents = Etorrent.get_all_torrent_metrics()

    render(conn, :index, torrents: torrents, torrent_changeset: Phoenix.Component.to_form(%{}))
  end

  def create(
        conn,
        %{"torrent_file" => torrent_file, "data_path" => dangerous_data_path} = _params
      ) do
    f = File.read!(torrent_file.path)

    {:ok, decoded_torrent_file} =
      Bencode.decode(f, atom_keys: true)

    Etorrent.new_torrent(decoded_torrent_file, dangerous_data_path)

    conn
    |> redirect(to: ~p"/")
  end

  def show(conn, %{"info_hash" => info_hash_hex} = _params) do
    info_hash = Base.decode16!(info_hash_hex)

    {:ok, torrent} = Etorrent.get_torrent_metrics(info_hash)

    {cols, rows} = make_square_from_list(length(torrent[:pieces]))

    conn
    |> render(:show, torrent: torrent, cols: cols, rows: rows)
  end

  def make_square_from_list(i) do
    base = :math.sqrt(i) |> ceil()
    {base, base}
  end
end
