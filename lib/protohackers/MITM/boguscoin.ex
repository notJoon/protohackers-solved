defmodule Protohackers.MITM.Boguscoin do
  @address "7YWHMfk9JZe0LM0g1ZauHuiSxhI"

  def rewrite_address(given_address) when is_binary(given_address) do
    regex = ~r/(^|\s)\K(7[[:alnum:]]{25,34})(?=[^[:alnum:]]|\s|$)/
    Regex.replace(regex, given_address, @address)
  end
end
