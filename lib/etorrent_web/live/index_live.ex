# defmodule EtorrentWeb.IndexLive do
#   use EtorrentWeb, :live_view

#   def mount(_params, _session, socket) do
#     torrents = Etorrent.Torrent.get_all_torrent_metrics()

#     socket =
#       socket
#       |> assign(:torrents, torrents)
#       |> assign(:torrent_upload_form, to_form(%{"torrent_files" => []}))
#       |> allow_upload(:torrent_files, accept: ~w(.torrent), max_entries: 100)

#     {:ok, socket}
#   end

#   def handle_event("change-torrent-files", unsigned_params, socket) do
#     dbg(unsigned_params)
#     {:noreply, socket}
#   end

#   def handle_event("save-torrent-files", unsigned_params, socket) do
#     # IO.inspect(1..100, label: "a wonderful range")
#     # IO.inspect(unsigned_params, label: "SAVE TORRENT FILES")
#     consume_uploaded_entries(socket, :torrent_files, fn %{path: path}, entry ->
#       # IO.inspect(entry)
#       # IO.inspect(path, label: "UPLOAD PATH")
#       {:ok, "foo"}
#     end)

#     dbg(unsigned_params)
#     {:noreply, socket}
#   end

#   def render(assigns) do
#     ~H"""
#     <Layouts.flash_group flash={@flash} />

#     <div>
#       <.form
#         for={@torrent_upload_form}
#         phx-change="change-torrent-files"
#         phx-submit="save-torrent-files"
#       >
#         <fieldset class="fieldset">
#           <label class="label" for="torrent_files">Choose torrent files to upload (.torrent)</label>
#           <.live_file_input
#             class="file-input"
#             upload={@uploads.torrent_files}
#           />
#         </fieldset>
#         <button type="submit" class="btn">Submit</button>
#       </.form>

#       <table class="table">
#         <thead>
#           <tr>
#             <th>Name</th>
#             <th>Size (bytes)</th>
#             <th>Progress</th>
#             <th>Download</th>
#             <th>Upload</th>
#             <th>Peers</th>
#             <th>Ratio</th>
#             <th></th>
#           </tr>
#         </thead>
#         <tbody id="torrents-table">
#           <tr :for={torrent <- @torrents}>
#             <td>{torrent[:name]}</td>
#             <td>{torrent[:size]}</td>
#             <%!-- <td>{torrent[:progress]}</td> --%>
#             <td>
#               <progress
#                 class="progress"
#                 value="10"
#                 max="100"
#               >
#               </progress>
#             </td>
#             <td>{torrent[:download]}</td>
#             <td>{torrent[:upload]}</td>
#             <td>{torrent[:peers]}</td>
#             <td>{torrent[:ratio]}</td>
#             <td>
#               <a
#                 :if={torrent[:state] == :active}
#                 class="link"
#                 hx-put={"/torrents/pause/#{torrent[:info_hash]}"}
#               >
#                 Pause
#               </a>
#               <a
#                 :if={torrent[:state] == :paused}
#                 class="link"
#                 hx-put={"/torrents/resume/#{torrent[:info_hash]}"}
#               >
#                 Resume
#               </a>
#             </td>
#           </tr>
#         </tbody>
#       </table>
#     </div>
#     """
#   end
# end
