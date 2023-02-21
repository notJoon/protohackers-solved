defmodule Protohackers.MITM.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  @impl true
  def init(:no_args) do
    children = [
      Protohackers.MITM.Accepter,
      Protohackers.MITM.ConnectionSupervisor
    ]

    # use `:rest_for_one` strategy to restart all children if one of them fails
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
