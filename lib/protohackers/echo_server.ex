defmodule Protohackers.EchoServer do
  use GenServer

  require Logger

  @port 5001

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [:listen_socket, :supervisor]

  @impl true
  def init(:no_state) do
    Logger.info("Starting echo server")

    # handling concurrent connections
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      # sent and received data will represent as binaries
      mode:       :binary,

      # actions on the socket need to be explicit and blocking
      active:     false,

      # reuse the port if it's already in use
      reuseaddr:  true,

      # allows write to a closed socket
      exit_on_close: false,
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
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
          fn -> handle_connection(socket)
        end)

        # continue accepting new connections
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp handle_connection(socket) do
    case recv_until_closed(socket, _buffer = "", _buffer_size = 0) do
      {:ok, data} ->
        :gen_tcp.send(socket, data)

      {:error, reason} ->
        Logger.error("Failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  @limit _100_kb = 100 * 1024

  defp recv_until_closed(socket, buffer, buffer_size) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      # to prevent buffer overflow
      {:ok, data} when buffer_size + byte_size(data) > @limit ->
        {:error, :buffer_overflow}

      {:ok, data} ->
        recv_until_closed(socket, [buffer, data], buffer_size + byte_size(data))

      {:error, :closed} -> {:ok, buffer}

      {:error, reason} -> {:error, reason}
    end
  end
end
