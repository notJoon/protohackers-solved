defmodule Protohackers.SpeedCamera.CentralTicketDispatcher do
  use GenServer

  alias Protohackers.SpeedCamera.{DispatcherRegistry, Message}

  require Logger

  @seconds_per_day 86_400

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  @spec add_road(:road_id, :speed_limit) :: GenServer.on_cast()
  def add_road(road, speed_limit) do
    GenServer.cast(__MODULE__, {:add_road, road, speed_limit})
  end

  @spec register_observation(:road_id, :location, :plate, :timestamp) :: GenServer.on_cast()
  def register_observation(road, loc, plate, timestamp) do
    GenServer.cast(__MODULE__, {:register_observation, road, loc, plate, timestamp})
  end

  ## State
  defmodule Road do
    defstruct [:id, :speed_limit, observations: %{}, pending_tickets: []]
  end

  defstruct roads: %{}, sent_tickets_per_day: []

  ## Callbacks

  @impl true
  @spec init(:no_args) :: {:ok, %__MODULE__{}}
  def init(:no_args) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  @spec handle_cast(any, %__MODULE__{}) :: {:noreply, %__MODULE__{}}
  def handle_cast(cast, state)

  def handle_cast({:add_road, road_id, speed_limit}, state) do
    Logger.debug("Adding road #{road_id} with speed limit #{speed_limit}")

    new_road = %Road{id: road_id, speed_limit: speed_limit}
    state = update_in(state.roads, &Map.put_new(&1, road_id, new_road))

    {:noreply, state}
  end

  def handle_cast({:register_observation, road_id, loc, plate, timestamp}, state) do
    state =
      update_in(
        state.roads[road_id].observations[plate],
        fn observations ->
          observations = observations || []
          [{timestamp, loc}] ++ observations
        end
      )

    road = generate_tickets(state.roads[road_id], plate)

    state = put_in(state.roads[road_id], road)
    state = dispatch_tickets_to_available_dispatchers(state, road_id)

    {:noreply, state}
  end

  @impl true
  @spec handle_info(any, %__MODULE__{}) :: {:noreply, %__MODULE__{}}
  def handle_info(info, state)

  def handle_info({:register, DispatcherRegistry, road_id, _partition, _value}, state) do
    state = dispatch_tickets_to_available_dispatchers(state, road_id)

    {:noreply, state}
  end

  # do nothing
  def handle_info({:unregister, DispatcherRegistry, _dispatcher, _partition}, state) do
    {:noreply, state}
  end

  ## Helpers

  @spec generate_tickets(%Road{}, :plate) :: %Road{}
  defp generate_tickets(%Road{} = road, plate) do
    observations = get_observations(road, plate)
    tickets = get_tickets(road, plate, observations)

    %Road{road | pending_tickets: road.pending_tickets ++ tickets}
  end

  @spec dispatch_tickets_to_available_dispatchers(%__MODULE__{}, :road_id) :: %__MODULE__{}
  defp dispatch_tickets_to_available_dispatchers(state, road_id) do
    case Map.fetch(state.roads, road_id) do
      {:ok, %Road{} = road} ->
        {tickets_left_to_dispatch, sent_tickets_per_day} =
          Enum.flat_map_reduce(
            state.roads[road_id].pending_tickets,
            state.sent_tickets_per_day,
            fn ticket, acc ->
              case Registry.lookup(DispatchersRegistry, road.id) do
                [] ->
                  Logger.debug("No dispatchers available for road #{ticket.road}, keeping ticket")
                  {[ticket], acc}

                dispatchers ->
                  ticket_start_day = floor(ticket.timestamp1 / @seconds_per_day)
                  ticket_end_day = floor(ticket.timestamp2 / @seconds_per_day)

                  if {ticket_start_day, ticket.plate} in acc or
                       {ticket_end_day, ticket.plate} in acc do
                    Logger.debug(
                      "already sent for this day: #{inspect(ticket)} for plate #{ticket.plate}"
                    )

                    {[], acc}
                  else
                    {pid, _} = Enum.random(dispatchers)
                    GenServer.cast(pid, {:dispatch_ticket, ticket})

                    sent = for day <- ticket_start_day..ticket_end_day, do: {day, ticket.plate}
                    {[], acc ++ sent}
                  end
              end
            end
          )

        state = put_in(state.sent_tickets_per_day, sent_tickets_per_day)
        state = put_in(state.roads[road_id].pending_tickets, tickets_left_to_dispatch)
        state

      :error ->
        state
    end
  end

  @spec get_observations(Road.t(), :plate) :: [{:timestamp, :location}]
  defp get_observations(%Road{} = road, plate) do
    observations =
      road.observations[plate]
      |> Enum.sort_by(fn {timestamp, _loc} -> timestamp end)
      |> Enum.dedup_by(fn {timestamp, _loc} -> timestamp end)

    observations
  end

  @spec get_tickets(Road.t(), :plate, [{:timestamp, :location}]) :: [Message.Ticket.t()]
  defp get_tickets(%Road{} = road, plate, observations) do
    tickets =
      observations
      |> Stream.zip(Enum.drop(observations, 1))
      |> Enum.flat_map(fn {{timestamp1, loc1}, {timestamp2, loc2}} ->
        distance = abs(loc1 - loc2)
        time_diff = timestamp1 - timestamp2
        miles_per_hour = round(distance / time_diff * 3600) * 100

        if miles_per_hour > road.speed_limit do
          [
            %Message.Ticket{
              plate: plate,
              road: road.id,
              start_mile: loc1,
              timestamp_on: timestamp1,
              end_mile: loc2,
              timestamp_off: timestamp2,
              speed: miles_per_hour
            }
          ]
        else
          []
        end
      end)

    tickets
  end
end
