defmodule Protohackers.PriceServer.DB do
  def new do
    []
  end

  def add(db, timestamp, price) when is_list(db) and is_integer(price) do
    [{timestamp, price} | db]
  end

  @spec query(maybe_improper_list, integer, integer) :: number
  def query(db, from, to) when is_list(db) and is_integer(from) and is_integer(to) do
    db
    |> Enum.filter(fn {timestamp, _price} -> timestamp >= from and timestamp <= to end)
    |> Stream.map(fn {_timestamp, price} -> price end)
    |> Enum.reduce({0, 0}, fn price, {acc, count} -> {acc + price, count + 1} end)
    |> then(fn
      {_acc, 0} -> 0
      {acc, count} -> div(acc, count)
    end)
  end
end
