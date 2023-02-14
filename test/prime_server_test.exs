defmodule Protohackers.PrimeServerTest do
  use ExUnit.Case

  @port 5002

  test "returns JSON" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

    :gen_tcp.send(socket, Jason.encode!(%{method: "isPrime", number: 7}) <> "\n")
    assert {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
    assert String.ends_with?(data, "\n")
    assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => true}

    :gen_tcp.send(socket, Jason.encode!(%{method: "isPrime", number: 6}) <> "\n")
    assert {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
    assert String.ends_with?(data, "\n")
    assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => false}
  end
end
