defmodule Protohackers.SpeedCamera.Connection do
  use GenServer, restart: :temporary

  alias Protohackers.SpeedCamera.{
    CentralTicketDispatcher,
    DispatcherRegistry,
    Message
  }

  require Logger

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [:socket, :type, :heartbeat_ref, buffer: <<>>]

  @impl true
  def init(socket) do
    Logger.debug("Client connected: #{inspect(socket)}")

    {:ok, %__MODULE__{socket: socket}}
  end

  @impl true
  def handle_info(message, state)

  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket} = state) do
    state = update_in(state.buffer, &(&1 <> data))
    :ok = :inet.setopts(socket, active: :once)

    parse_all(state)
  end

  def handle_info({:tcp_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    Logger.error("Connection closed: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    Logger.debug("Connection closed by client")
    {:stop, :normal, state}
  end

  def handle_info(:send_heartbeat, %__MODULE__{} = state) do
    send_message(state, %Message.Heartbeat{})
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:dispatche_ticket, ticket},
        %__MODULE__{type: %Message.TicketDispatcher{}} = state
      ) do
    send_message(state, ticket)
    {:noreply, state}
  end

  #### helpers

  defp send_message(%__MODULE__{socket: socket}, message) do
    Logger.debug("Sending message: #{inspect(message)}")
    :gen_tcp.send(socket, Message.encode(message))
  end

  defp parse_all(%__MODULE__{} = state) do
    case Message.decode(state.buffer) do
      {:ok, msg, rest} ->
        Logger.debug("Received message: #{inspect(msg)}")
        state = put_in(state.buffer, rest)

        case handle_message(state, msg) do
          {:ok, state} ->
            parse_all(state)

          {:error, message} ->
            send_message(state, %Message.Error{message: message})
            {:stop, :normal, state}
        end
    end
  end

  defp handle_message(
         %__MODULE__{type: %Message.Camera{} = camera} = state,
         %Message.Plate{} = message
       ) do
    CentralTicketDispatcher.register_observation(
      camera.road,
      camera.mile,
      message.plate,
      message.timestamp
    )

    {:ok, state}
  end

  defp handle_message(%__MODULE__{type: _other}, %Message.Plate{}) do
    {:error, "Plate message received before camera message"}
  end

  defp handle_message(state, %Message.WantHeartbeat{interval: interval}) do
    interval_ms = interval * 100

    if state.heartbeat_ref do
      :timer.cancel(state.heartbeat_ref)
    end

    if interval > 0 do
      {:ok, hb_ref} = :timer.send_interval(interval_ms, :send_heartbeat)
      {:ok, %__MODULE__{state | heartbeat_ref: hb_ref}}
    else
      {:ok, %__MODULE__{state | heartbeat_ref: nil}}
    end
  end

  defp handle_message(%__MODULE__{type: _other} = state, %Message.Camera{}) do
    {:error, "Already registered as #{inspect(state.type)}"}
  end

  defp handle_message(%__MODULE__{type: nil} = state, %Message.TicketDispatcher{} = message) do
    Enum.each(message.roads, fn road ->
      {:ok, _} = Registry.register(DispatcherRegistry, road, :unused_value)
    end)

    Logger.metadata(type: :dispatcher)

    {:ok, %__MODULE__{state | type: message}}
  end

  defp handle_message(%__MODULE__{type: _other}, %Message.TicketDispatcher{}) do
    {:error, "Already registered as a dispatcher or camera"}
  end

  defp handle_message(%__MODULE__{}, _msg) do
    {:error, "Unknown message"}
  end
end
