defmodule Etorrent.Repo do
  use Ecto.Repo,
    otp_app: :etorrent,
    adapter: Ecto.Adapters.SQLite3
end
