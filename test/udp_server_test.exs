defmodule Protohackers.UDPServerTest do
  use ExUnit.Case, async: true

  @host {127, 0, 0, 1}
  @port 5005

  test "insert and retrieve request" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, recbuf: 1000])

    :ok = :gen_udp.send(socket, @host, @port, "foo=1")
    :ok = :gen_udp.send(socket, @host, @port, "foo")
    assert {:ok, {_address, _port, "foo=1"}} = :gen_udp.recv(socket, 0)

    :ok = :gen_udp.send(socket, @host, @port, "foo=2")
    :ok = :gen_udp.send(socket, @host, @port, "foo")
    assert {:ok, {_address, _port, "foo=2"}} = :gen_udp.recv(socket, 0)
  end

  test "version request" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, recbuf: 1000])

    :ok = :gen_udp.send(socket, @host, @port, "version")
    assert {:ok, {_address, _port, "version=UDP Server 1.0"}} = :gen_udp.recv(socket, 0)
  end
end
