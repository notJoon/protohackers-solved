defmodule Protohackers.SpeedCamera.Supervisor do
  use Supervisor

  alias Protohackers.SpeedCamera

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    registry_opts = [
      name: SpeedCamera.DispatchersRegistry,
      keys: :duplicate,
      listeners: [SpeedCamera.CentralTicketDispatcher]
    ]

    children = [
      {Registry, registry_opts},
      {SpeedCamera.CentralTicketDispatcher, []},
      {SpeedCamera.ConnectionSupervisor, []},
      {SpeedCamera.Accepter, opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
