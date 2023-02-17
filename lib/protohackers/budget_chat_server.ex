defmodule Protohackers.BudgetChatServer do
  use GenServer

  require Logger

  @port 5004

  @spec start_link([]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [:listen_socket, :supervisor, :ets]

  @impl true
  def init(:no_state) do
    Logger.info("Starting chat server")

    # handling concurrent connections
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    ets = :ets.new(__MODULE__, [:public])

    listen_options = [
      ifaddr:         {0, 0, 0, 0},

      # sent and received data will represent as binaries
      mode:           :binary,

      # actions on the socket need to be explicit and blocking
      active:         false,

      # reuse the port if it's already in use
      reuseaddr:      true,

      # allows write to a closed socket
      exit_on_close:  false,

      # Line mode, a packet is a line-terminated with newline,
      # lines longer than the receive buffer are truncated
      packet:         :line,

      buffer:         1024 * 100,
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        dbg(:inet.getopts(listen_socket, [:buffer]))
        Logger.info("Listening on port #{@port}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor, ets: ets}
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
          fn -> handle_connection(socket, state.ets)
        end)

        # continue accepting new connections
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp handle_connection(socket, ets) do
    :ok = :gen_tcp.send(socket, "What's your username?\n")

    case :gen_tcp.recv(socket, 0, 300_000) do
      {:ok, line} ->
        username = String.trim(line)

        if username =~ ~r/^[[:alnum:]]+$/ do
          Logger.debug("Username #{username} connected")

          # only cares `username`
          all_users = :ets.match(ets, :"$1")
          usernames = Enum.map_join(all_users, ", ", fn [{_socket, username}] -> username end)
          :ets.insert(ets, {socket, username})

          Enum.each(all_users, fn [{socket, _username}] ->
            :gen_tcp.send(socket, "* #{username} has entered the chat\n")
          end)

          :ok = :gen_tcp.send(socket, "* The room contains: #{usernames}\n")
          handle_chat_session(socket, ets, username)
        else
          :ok = :gen_tcp.send(socket, "Invalid username\n")
          :gen_tcp.close(socket)
        end

        {:error, _reason} ->
          :gen_tcp.close(socket)
          :ok
    end
  end

  defp handle_chat_session(socket, ets, username) do
    case :gen_tcp.recv(socket, 0, 300_000) do
      {:ok, msg} ->
        msg = msg |> String.trim()

        if msg != "" do
          all_sockets = :ets.match(ets, {:"$1", :_})

          for [other_socket] <- all_sockets, other_socket != socket do
            :gen_tcp.send(other_socket, "[#{username}] #{msg}\n")
          end
        end

        handle_chat_session(socket, ets, username)

      {:error, _reason} ->
        all_sockets = :ets.match(ets, {:"$1", :_})

        for [other_socket] <- all_sockets, other_socket != socket do
          :gen_tcp.send(other_socket, "* #{username} left\n")
        end

      _ = :gen_tcp.close(socket)
      :ets.delete(ets, socket)
    end
  end
end
