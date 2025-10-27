defmodule EtorrentWeb.TorrentController do
  use EtorrentWeb, :controller

  alias Etorrent.Bencode

  def index(conn, _params) do
    torrents = Etorrent.get_all_torrent_metrics()

    render(conn, :index, torrents: torrents, torrent_changeset: Phoenix.Component.to_form(%{}))
  end

  def create(conn, %{"torrent_files" => torrent_files} = _params) do
    Enum.each(torrent_files, fn file ->
      f = File.read!(file.path)

      {:ok, torrent_file} =
        Bencode.decode(f, atom_keys: true)

      Etorrent.new_torrent(torrent_file)
    end)

    torrents = Etorrent.get_all_torrent_metrics()

    conn
    |> render(:created, torrents: torrents)
  end

  def show(conn, %{"info_hash" => info_hash_hex} = _params) do
    info_hash = Base.decode16!(info_hash_hex)

    {:ok, torrent} = Etorrent.get_torrent_metrics(info_hash)

    conn
    |> render(:show, torrent: torrent)
  end
end
