defmodule Etorrent.AcceptorSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    children =
      Enum.map(1..init_arg, fn i ->
        {Etorrent.AcceptorWorker, i}
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
