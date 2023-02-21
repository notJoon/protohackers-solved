defmodule Protohackers.MITM.Accepter do
  use Task, restart: :transient

  require Logger

  @port 5006

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link([] = _opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  @spec run :: no_return()
  def run do
    case :gen_tcp.listen(
           @port,
           [
             :binary,
             ifaddr: {0, 0, 0, 0},
             active: :once,
             packet: :line,
             reuseaddr: true
           ]
         ) do
      {:ok, listen_socket} ->
        Logger.info("Listening on port #{@port}")
        accept_loop(listen_socket)

      {:error, reason} ->
        raise "Failed to listen on port #{@port}: #{inspect(reason)}"
    end
  end

  @spec accept_loop(:gen_tcp.socket()) :: no_return()
  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        Protohackers.MITM.ConnectionSupervisor.start_child(socket)

      {:error, reason} ->
        raise "Failed to accept connection: #{inspect(reason)}"
    end
  end
end
