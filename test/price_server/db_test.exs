defmodule Protohackers.PriceServer.DbTest do
  use ExUnit.Case, async: true

  alias Protohackers.PriceServer.DB

  test "adding elements and returns average" do
    db = DB.new()

    assert DB.query(db, 0, 100) == 0

    db =
      db
      |> DB.add(1, 10)
      |> DB.add(2, 20)
      |> DB.add(3, 30)

    assert DB.query(db, 0, 100) == 20
    assert DB.query(db, 0, 2) == 15
    assert DB.query(db, 2, 3) == 25
    assert DB.query(db, 4, 100) == 0
  end
end
