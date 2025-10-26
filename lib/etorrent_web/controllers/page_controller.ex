defmodule EtorrentWeb.PageController do
  use EtorrentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
