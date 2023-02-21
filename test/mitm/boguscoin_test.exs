defmodule Protohackers.MITM.BoguscoinTest do
  use ExUnit.Case, async: true

  alias Protohackers.MITM.Boguscoin

  @address "7YWHMfk9JZe0LM0g1ZauHuiSxhI"

  @sample_address [
    "7F1u3wSD5RbOHQmupo9nx4TnhQ",
    "7iKDZEwPZSqIvDnHvVN2r0hUWXD5rHX",
    "7LOrwbDlS8NujgjddyogWgIM93MV5N2VR",
    "7adNeSwJkMakpEcln9HEtthSRtxdmEHOT8T"
  ]

  describe "rewrite address/1" do
    test "do not anything if address is invalid" do
      assert Boguscoin.rewrite_address("hello") == "hello"
    end

    test "ignore too long address" do
      addr = "7adgjddyogWwJkMNthSRtxdmeSOHQmupo9nx4TnNujgjddyogWwJkMakpEco9nxl"

      assert Boguscoin.rewrite_address(addr) == addr
    end

    test "multiple addresses" do
      assert Boguscoin.rewrite_address(Enum.join(@sample_address, " ")) ==
              Enum.join(
                List.duplicate(
                  @address,
                  length(@sample_address)
                ),
                " "
              )
    end

    test "with sample address" do
      for address <- @sample_address do
        assert Boguscoin.rewrite_address(address) == @address
        assert Boguscoin.rewrite_address(address <> " foo") == @address <> " foo"
        assert Boguscoin.rewrite_address("foo " <> address) == "foo " <> @address
        assert Boguscoin.rewrite_address("foo " <> address <> " bar") ==
                "foo " <> @address <> " bar"
      end
    end

  end
end
