defmodule EtorrentWeb.TorrentHTML do
  @moduledoc """
  This module contains pages rendered by TorrentController.

  See the `torrent_html` directory for all templates available.
  """
  use EtorrentWeb, :html

  embed_templates "torrent_html/*"

  attr :torrents, :list
  attr :rest, :global

  def torrents_table(assigns) do
    ~H"""
    <table id="torrents-table" class="table" {@rest}>
      <thead>
        <tr>
          <th>Name</th>
          <th>Size (bytes)</th>
          <th>Progress</th>
          <th>Download</th>
          <th>Upload</th>
          <th>Peers</th>
          <th>Ratio</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={torrent <- @torrents}>
          <td>
            <a class="link" href={"/torrents/#{torrent[:info_hash]}/show"}>
              {torrent[:name]}
            </a>
          </td>
          <td>{torrent[:size]}</td>
          <td>
            <progress
              class="progress"
              value={
                torrent[:pieces]
                |> Enum.filter(fn piece -> piece end)
                |> Enum.count()
                |> then(fn haves -> haves / length(torrent[:pieces]) end)
              }
            >
            </progress>
          </td>
          <td>{torrent[:download]}</td>
          <td>{torrent[:upload]}</td>
          <td>{inspect(torrent[:peers])}</td>
          <td>{torrent[:ratio]}</td>
          <td>
            <a
              :if={torrent[:state] == :active}
              class="link"
              hx-put={"/torrents/pause/#{torrent[:info_hash]}"}
            >
              Pause
            </a>
            <a
              :if={torrent[:state] == :paused}
              class="link"
              hx-put={"/torrents/resume/#{torrent[:info_hash]}"}
            >
              Resume
            </a>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end
end
