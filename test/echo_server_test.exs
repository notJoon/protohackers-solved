defmodule Protohackers.EchoServerTest do
  use ExUnit.Case

  test "echos any message" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5001, mode: :binary, active: false)

    assert :gen_tcp.send(socket, "hello") == :ok
    assert :gen_tcp.send(socket, " ") == :ok
    assert :gen_tcp.send(socket, "world") == :ok

    :gen_tcp.shutdown(socket, :write)

    assert :gen_tcp.recv(socket, 0, 5000) == {:ok, "hello world"}
  end

  @tag :capture_log
  test "echo server has max buffer size" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5001, mode: :binary, active: false)

    assert :gen_tcp.send(socket, :binary.copy("a", 1024 * 100 + 1))
    assert :gen_tcp.recv(socket, 0) == {:error, :closed}
  end

  test "handle multiple concurrent connections" do
    tasks =
      for _ <- 1..4 do
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.connect(~c"localhost", 5001, mode: :binary, active: false)
          assert :gen_tcp.send(socket, "hello") == :ok
          assert :gen_tcp.send(socket, " ") == :ok
          assert :gen_tcp.send(socket, "world") == :ok

          :gen_tcp.shutdown(socket, :write)

          assert :gen_tcp.recv(socket, 0, 5000) == {:ok, "hello world"}
        end)
      end

      Enum.each(tasks, &Task.await/1)
  end
end
