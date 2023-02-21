defmodule Protohackers.SpeedCamera.IntegrationTest do
  use ExUnit.Case

  alias Protohackers.SpeedCamera.Message

  @port 5007

  test "on a single car" do
    {:ok, camera1} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    {:ok, dispatcher} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])

    send_message(dispatcher, %Message.TicketDispatcher{roads: [582]})

    send_message(camera1, %Message.Camera{road: 582, mile: 4452, limit: 100})
    send_message(camera1, %Message.Plate{plate: "UK43PKD", timestamp: 203_663})

    send_message(camera2, %Message.Camera{road: 582, mile: 4462, limit: 100})
    send_message(camera2, %Message.Plate{plate: "UK43PKD", timestamp: 203_963})

    assert_receive {:tcp, ^dispatcher, data}
    assert {:ok, message, <<>>} = Message.decode(data)

    assert message == %Message.Ticket{
             start_mile: 4452,
             end_mile: 4462,
             plate: "UK43PKD",
             road: 582,
             speed: 12000,
             timestamp_on: 203_663,
             timestamp2_off: 203_963
           }
  end

  test "pending tickets get flushed" do
    {:ok, camera1} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    {:ok, camera2} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    send_message(camera1, %Message.Camera{road: 582, mile: 4452, limit: 100})
    send_message(camera2, %Message.Camera{road: 582, mile: 4462, limit: 100})
    send_message(camera1, %Message.Plate{plate: "IT43PRC", timestamp: 203_663})
    send_message(camera2, %Message.Plate{plate: "IT43PRC", timestamp: 203_963})

    # We now have a tickets on road 582, but no dispatcher for it.

    {:ok, dispatcher} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: true])
    send_message(dispatcher, %Message.TicketDispatcher{roads: [582]})

    assert_receive {:tcp, ^dispatcher, data}
    assert {:ok, message, <<>>} = Message.decode(data)

    assert message == %Message.Ticket{
             start_mile: 4452,
             end_mile: 4462,
             plate: "IT43PRC",
             road: 582,
             speed: 12000,
             timestamp_on: 203_663,
             timestamp_off: 203_963
           }
  end

  defp send_message(socket, msg) do
    assert :ok = :gen_tcp.send(socket, Message.encode(msg))
  end
end
