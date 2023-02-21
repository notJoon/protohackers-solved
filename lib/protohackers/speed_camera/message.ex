defmodule Protohackers.SpeedCamera.Message do
  @type_bytes [0x20, 0x40, 0x80, 0x01, 0x02, 0x04, 0x08]

  defmodule Plate do
    defstruct [:plate, :timestamp]
  end

  # Server -> Client
  #
  # when the server detects that a car's avg speed is above the limit, it generates a `Ticket`
  # message and sends it to the client.
  defmodule Ticket do
    defstruct [:plate, :road, :start_mile, :timestamp_on, :end_mile, :timestamp_off, :speed]
  end

  # Client -> Server
  #
  # [Fields]
  #  - `num_roads`: u8, how many roads this dispatcher is responsible for
  #  - `road`: [u16], contains the road numbers
  defmodule TicketDispatcher do
    defstruct [:roads]
  end

  # No fields
  #
  # Send to a client at the interval requested by the client.
  defmodule Heartbeat do
    defstruct []
  end

  # Client -> Server
  #
  # [Fields]
  #  - `interval`: u32, the interval in deciseconds
  #
  # An interval of 0 deciseconds means the client does not want to receive heartbeats.
  #
  # [Error]
  # send multiple `WantHeartbeat` messages on a single connection.
  defmodule WantHeartbeat do
    defstruct [:interval]
  end

  # Client -> Server
  #
  # [Error]
  # Client has already identified itself as either a camera or a ticket dispatcher
  # to send an `Camera` message/
  defmodule Camera do
    defstruct [:road, :mile, :limit]
  end

  # the server must send the client an `Error` message and
  # immediately close the connection.
  defmodule Error do
    defstruct [:message]
  end

  @spec encode(message) :: binary()
        when message: term()

  def encode(%Error{message: message}) do
    <<0x10, byte_size(message), message::binary>>
  end

  def encode(%Plate{} = plate) do
    <<0x20, byte_size(plate.plate)::8, plate.plate::binary, plate.timestamp::32>>
  end

  def encode(%Ticket{} = ticket) do
    <<0x21, byte_size(ticket.plate), ticket.plate::binary, ticket.road::16, ticket.start_mile::16,
      ticket.timestamp_on::32, ticket.end_mile::16, ticket.timestamp_off::32, ticket.speed::16>>
  end

  def encode(%WantHeartbeat{interval: interval}) do
    <<0x40, interval::32>>
  end

  def encode(%Heartbeat{}) do
    <<0x41>>
  end

  def encode(%Camera{road: road, mile: mile, limit: limit}) do
    <<0x80, road::16, mile::16, limit::16>>
  end

  def encode(%TicketDispatcher{roads: roads}) do
    encoded = IO.iodata_to_binary(for road <- roads, do: <<road::16>>)
    <<0x81, length(roads)::8, encoded::binary>>
  end

  @spec decode(binary) :: {:ok, message, binary}
        when message: term()

  def decode(binary)

  # Error
  def decode(<<0x10, size::8, message::size(size)-binary, rest::binary>>) do
    {:ok, %Error{message: message}, rest}
  end

  # Plate
  def decode(<<0x20, plate_size::8, plate::binary-size(plate_size), timestamp::32, rest::binary>>) do
    message = %Plate{plate: plate, timestamp: timestamp}
    {:ok, message, rest}
  end

  # WantHeartbeat
  def decode(<<0x40, interval::32, rest::binary>>) do
    {:ok, %WantHeartbeat{interval: interval}, rest}
  end

  # Heartbeat
  def decode(<<0x41, rest::binary>>) do
    {:ok, %Heartbeat{}, rest}
  end

  # Camera
  def decode(<<0x80, road::16, mile::16, limit::16, rest::binary>>) do
    {:ok, %Camera{road: road, mile: mile, limit: limit}, rest}
  end

  # TicketDispatcher
  def decode(<<0x81, num_roads::8, roads::binary-size(num_roads * 2), rest::binary>>) do
    roads = for <<road::16 <- roads>>, do: road
    {:ok, %TicketDispatcher{roads: roads}, rest}
  end

  # Ticket
  def decode(
        <<0x21, plate_size::8, plate::size(plate_size)-binary, road::16, start_mile::16,
          timestamp_on::32, end_mile::16, timestamp_off::32, speed::16, rest::binary>>
      ) do
    message = %Ticket{
      plate: plate,
      road: road,
      start_mile: start_mile,
      timestamp_on: timestamp_on,
      end_mile: end_mile,
      timestamp_off: timestamp_off,
      speed: speed
    }

    {:ok, message, rest}
  end

  def decode(<<byte, _rest::binary>>) when byte in @type_bytes do
    :incomplete
  end

  def decode(<<_byte, _rest::binary>>) do
    :error
  end

  def decode(<<>>) do
    :incomplete
  end
end
