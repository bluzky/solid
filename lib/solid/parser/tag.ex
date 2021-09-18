defmodule Solid.Parser.Tag do
  import NimbleParsec
  alias Solid.Parser.Literal

  @space Literal.whitespace(min: 0)

  def opening_tag() do
    string("{%")
    |> concat(optional(string("-")))
    |> concat(@space)
  end

  def closing_tag() do
    closing_wc_tag_and_whitespace =
      string("-%}")
      |> concat(@space)
      |> ignore()

    @space
    |> concat(choice([closing_wc_tag_and_whitespace, string("%}")]))
  end
end
