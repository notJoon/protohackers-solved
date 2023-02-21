defmodule Protohackers.MITM.Connection do
  use GenServer

  require Logger

  @spec start_link(:gen_tcp.socket()) :: GenServer.on_start()
  def start_link(incoming_socket) do
    GenServer.start_link(__MODULE__, incoming_socket)
  end

  defstruct [:incoming_socket, :outgoing_socket]

  @impl true
  @spec init(:gen_tcp.socket()) :: {:ok, %__MODULE__{}} | {:stop, any()}
  def init(incoming_socket) do
    case :gen_tcp.connect(~c"chat.protohackers.com", 16963, [:binary, active: :once]) do
      {:ok, outgoing_socket} ->
        Logger.debug("Connected to chat.protohackers.com:16963")
        {:ok, %__MODULE__{incoming_socket: incoming_socket, outgoing_socket: outgoing_socket}}

      {:error, reason} ->
        Logger.error("Failed to connect to chat.protohackers.com:16963: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  @spec handle_info(any(), %__MODULE__{})
      :: {:noreply, %__MODULE__{}} | {:stop, any(), %__MODULE__{}}
  def handle_info(msg, state)

  def handle_info(
        {:tcp, incoming_socket, data},
        %__MODULE__{incoming_socket: incoming_socket} = state
      ) do
    :ok = :inet.setopts(incoming_socket, active: :once)
    Logger.debug("Received data: #{inspect(data)}")
    data = Protohackers.MITM.Boguscoin.rewrite_address(data)
    :gen_tcp.send(state.outgoing_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp, outgoing_socket, data},
        %__MODULE__{outgoing_socket: outgoing_socket} = state
      ) do
    :ok = :inet.setopts(outgoing_socket, active: :once)
    Logger.debug("Received data: #{inspect(data)}")
    data = Protohackers.MITM.Boguscoin.rewrite_address(data)
    :gen_tcp.send(state.incoming_socket, data)
    {:noreply, state}
  end

  def handle_info(
        {:tcp_error, socket, reason},
        %__MODULE__{} = state
      )
      when socket in [state.incoming_socket, state.outgoing_socket] do
    Logger.error("Received TCP error: #{inspect(reason)}")
    :gen_tcp.close(state.incoming_socket)
    :gen_tcp.close(state.outgoing_socket)
    {:stop, reason, state}
  end

  def handle_info(
        {:tcp_closed, socket},
        %__MODULE__{} = state
      )
      when socket in [state.incoming_socket, state.outgoing_socket] do
    Logger.debug("TCP connection closed")
    :gen_tcp.close(state.incoming_socket)
    :gen_tcp.close(state.outgoing_socket)
    {:stop, :normal, state}
  end
end
