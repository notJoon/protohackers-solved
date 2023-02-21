defmodule Protohackers.PrimeServer do
  use GenServer

  require Logger

  @port 5002

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [:listen_socket, :supervisor]

  @impl true
  def init(:no_state) do
    Logger.info("Starting prime server")

    # handling concurrent connections
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      # sent and received data will represent as binaries
      mode: :binary,

      # actions on the socket need to be explicit and blocking
      active: false,

      # reuse the port if it's already in use
      reuseaddr: true,

      # allows write to a closed socket
      exit_on_close: false,

      # Line mode, a packet is a line-terminated with newline,
      # lines longer than the receive buffer are truncated
      packet: :line,
      buffer: 1024 * 100
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        dbg(:inet.getopts(listen_socket, [:buffer]))
        Logger.info("Listening on port #{@port}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("Failed to listen on port #{@port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(
          state.supervisor,
          fn -> handle_connection(socket) end
        )

        # continue accepting new connections
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp handle_connection(socket) do
    case echo_lines_until_closed(socket) do
      {:error, reason} ->
        Logger.error("Failed to receive data: #{inspect(reason)}")

      _ ->
        :ok
    end

    :gen_tcp.close(socket)
  end

  defp echo_lines_until_closed(socket) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"method" => "isPrime", "number" => number}} when is_number(number) ->
            Logger.debug("received number: #{inspect(number)}")

            response = %{"method" => "isPrime", "prime" => is_prime?(number)}
            :gen_tcp.send(socket, [Jason.encode!(response), ?\n])

            socket |> echo_lines_until_closed()

          other ->
            Logger.debug("Received invalid request: #{inspect(other)}")
            :gen_tcp.send(socket, "malformed response\n")
            {:error, :invalid_request}
        end

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp is_prime?(number) when is_float(number), do: false
  defp is_prime?(number) when number <= 1, do: false
  defp is_prime?(number) when number in [2, 3], do: true

  defp is_prime?(number) do
    not Enum.any?(2..trunc(:math.sqrt(number)), &(rem(number, &1) == 0))
  end
end
