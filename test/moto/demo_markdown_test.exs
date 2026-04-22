defmodule MotoTest.DemoMarkdownTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Moto.Demo.Markdown

  test "formats common markdown for terminal output" do
    rendered =
      Markdown.format("""
      # Embeddings

      **Embeddings** are `vectors`.

      - Search
      - Recommendations
      """)

    assert rendered =~ "Embeddings"
    assert rendered =~ "Embeddings are vectors."
    assert rendered =~ "- Search"
    assert rendered =~ "- Recommendations"
    refute rendered =~ "**"
    refute rendered =~ "`vectors`"
  end

  test "prints simple replies inline" do
    assert capture_io(fn -> Markdown.print_reply("agent", "42") end) == "agent> 42\n"
  end

  test "prints multiline markdown below the speaker label" do
    output =
      capture_io(fn ->
        Markdown.print_reply("agent", "# Title\n\nA **bold** reply.")
      end)

    assert output =~ "agent>\n"
    assert output =~ "Title\n\nA bold reply."
  end
end
