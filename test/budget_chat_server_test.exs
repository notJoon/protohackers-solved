defmodule Protohackers.BudgetChatServerTest do
  use ExUnit.Case, async: true

  @port 5004
  @timeout 5_000
  test "basic chat server flow" do
    {:ok, socket1} =
      :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false, packet: :line)

    {:ok, socket2} =
      :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false, packet: :line)

    assert {:ok, "What's your username?\n"} = :gen_tcp.recv(socket1, 0, @timeout)
    :ok = :gen_tcp.send(socket1, "user1\n")
    assert {:ok, "* The room contains: \n"} = :gen_tcp.recv(socket1, 0, @timeout)

    assert {:ok, "What's your username?\n"} = :gen_tcp.recv(socket2, 0, @timeout)

    :ok = :gen_tcp.send(socket2, "user2\n")
    assert {:ok, "* The room contains: user1\n"} = :gen_tcp.recv(socket2, 0, @timeout)
    assert {:ok, "* user2 has entered the chat\n"} = :gen_tcp.recv(socket1, 0, @timeout)

    :ok = :gen_tcp.send(socket1, "Hello world!\n")
    assert {:ok, "[user1] Hello world!\n"} = :gen_tcp.recv(socket2, 0, @timeout)

    :ok = :gen_tcp.send(socket2, "Hi\n")
    assert {:ok, "[user2] Hi\n"} = :gen_tcp.recv(socket1, 0, @timeout)

    :gen_tcp.close(socket2)

    assert {:ok, "* user2 left\n"} = :gen_tcp.recv(socket1, 0, @timeout)

    {:ok, socket3} =
      :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false, packet: :line)

    assert {:ok, "What's your username?\n"} = :gen_tcp.recv(socket3, 0, @timeout)
    :ok = :gen_tcp.send(socket3, "user3\n")
    assert {:ok, "* The room contains: user1\n"} = :gen_tcp.recv(socket3, 0, @timeout)
  end
end
