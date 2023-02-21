defmodule Protohackers.PriceServer do
  use GenServer

  alias Protohackers.PriceServer.DB

  require Logger

  @port 5003

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [:listen_socket, :supervisor]

  @impl true
  def init(:no_state) do
    Logger.info("Starting price server")

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
      exit_on_close: false
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
    case handle_requests(socket, DB.new()) do
      :ok -> :ok
      {:error, reason} -> Logger.error("Failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  defp handle_requests(socket, db) do
    case :gen_tcp.recv(socket, 9, 10_000) do
      {:ok, data} ->
        case handle_request(data, db) do
          {nil, db} ->
            handle_requests(socket, db)

          {response, db} ->
            :gen_tcp.send(socket, response)
            handle_requests(socket, db)

          :error ->
            {:error, :invalid_request}
        end

      {:error, :timeout} ->
        handle_requests(socket, db)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_request(<<?I, timestamp::32-signed-big, price::32-signed-big>>, db) do
    {nil, DB.add(db, timestamp, price)}
  end

  defp handle_request(<<?Q, mintime::32-signed-big, maxtime::32-signed-big>>, db) do
    avg = DB.query(db, mintime, maxtime)
    {<<avg::32-signed-big>>, db}
  end

  defp handle_request(_other, _db), do: :error
end
