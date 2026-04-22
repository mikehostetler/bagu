defmodule Moto.Demo.Markdown do
  @moduledoc false

  @spec print_reply(String.t(), String.t()) :: :ok
  def print_reply(label, reply) when is_binary(label) and is_binary(reply) do
    rendered = format(reply)

    if single_line?(rendered) do
      IO.puts("#{label}> #{rendered}")
    else
      IO.puts("#{label}>")
      IO.puts(rendered)
    end
  end

  @spec format(String.t()) :: String.t()
  def format(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.parse_document()
    |> case do
      {:ok, %MDEx.Document{} = document} ->
        document
        |> render_document()
        |> IO.iodata_to_binary()
        |> String.trim_trailing()

      {:error, _reason} ->
        String.trim_trailing(markdown)
    end
  rescue
    _error -> String.trim_trailing(markdown)
  end

  defp render_document(%MDEx.Document{nodes: nodes}) do
    nodes
    |> Enum.map(&render_block(&1, 0))
    |> join_blocks()
  end

  defp render_block(%MDEx.Heading{nodes: nodes, level: level}, indent) do
    text = render_inline(nodes) |> String.trim()
    style(indent(indent) <> text, heading_style(level))
  end

  defp render_block(%MDEx.Paragraph{nodes: nodes}, indent) do
    indent(indent) <> (nodes |> render_inline() |> String.trim())
  end

  defp render_block(%MDEx.List{nodes: items, list_type: :ordered, start: start}, indent) do
    items
    |> Enum.with_index(start)
    |> Enum.map(fn {item, index} -> render_list_item(item, "#{index}.", indent) end)
    |> Enum.join("\n")
  end

  defp render_block(%MDEx.List{nodes: items}, indent) do
    items
    |> Enum.map(&render_list_item(&1, "-", indent))
    |> Enum.join("\n")
  end

  defp render_block(%MDEx.CodeBlock{literal: literal, info: info}, indent) do
    language =
      info
      |> to_string()
      |> String.trim()

    header =
      if language == "" do
        []
      else
        [indent(indent), style(language, [:faint]), "\n"]
      end

    body =
      literal
      |> String.trim_trailing()
      |> String.split("\n")
      |> Enum.map_join("\n", fn line -> indent(indent + 2) <> style(line, [:yellow]) end)

    [header, body]
  end

  defp render_block(%MDEx.BlockQuote{nodes: nodes}, indent) do
    nodes
    |> Enum.map(&render_block(&1, 0))
    |> join_blocks()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> indent(indent) <> style("> ", [:faint]) <> line end)
  end

  defp render_block(%MDEx.ThematicBreak{}, indent), do: indent(indent) <> style("----", [:faint])

  defp render_block(%MDEx.Table{nodes: rows}, indent), do: render_table(rows, indent)

  defp render_block(%{nodes: nodes}, indent) when is_list(nodes) do
    nodes
    |> Enum.map(&render_block(&1, indent))
    |> join_blocks()
  end

  defp render_block(node, indent), do: indent(indent) <> node_to_text(node)

  defp render_list_item(%MDEx.ListItem{nodes: nodes}, marker, indent) do
    {first, rest} =
      case nodes do
        [%MDEx.Paragraph{nodes: paragraph_nodes} | rest] ->
          {paragraph_nodes |> render_inline() |> String.trim(), rest}

        [node | rest] ->
          {render_block(node, 0) |> String.trim(), rest}

        [] ->
          {"", []}
      end

    prefix = indent(indent) <> marker <> " "
    continuation_indent = indent + String.length(marker) + 1

    tail =
      rest
      |> Enum.map(&render_block(&1, continuation_indent))
      |> reject_empty()
      |> case do
        [] -> ""
        blocks -> "\n" <> Enum.join(blocks, "\n")
      end

    prefix <> first <> tail
  end

  defp render_table(rows, indent) do
    rendered_rows =
      Enum.map(rows, fn %MDEx.TableRow{nodes: cells, header: header?} ->
        cells =
          Enum.map(cells, fn
            %MDEx.TableCell{nodes: nodes} -> nodes |> render_inline() |> String.trim()
            node -> node_to_text(node)
          end)

        {header?, cells}
      end)

    rendered_rows
    |> Enum.flat_map(fn
      {true, cells} ->
        [
          table_row(cells, indent),
          table_row(Enum.map(cells, fn _cell -> "---" end), indent)
        ]

      {false, cells} ->
        [table_row(cells, indent)]
    end)
    |> Enum.join("\n")
  end

  defp table_row(cells, indent), do: indent(indent) <> "| " <> Enum.join(cells, " | ") <> " |"

  defp render_inline(nodes) when is_list(nodes), do: Enum.map_join(nodes, &render_inline/1)

  defp render_inline(%MDEx.Text{literal: literal}), do: literal
  defp render_inline(%MDEx.SoftBreak{}), do: " "
  defp render_inline(%MDEx.LineBreak{}), do: "\n"
  defp render_inline(%MDEx.Code{literal: literal}), do: style(literal, [:yellow])
  defp render_inline(%MDEx.Strong{nodes: nodes}), do: nodes |> render_inline() |> style([:bright])
  defp render_inline(%MDEx.Emph{nodes: nodes}), do: nodes |> render_inline() |> style([:faint])
  defp render_inline(%MDEx.Strikethrough{nodes: nodes}), do: render_inline(nodes)

  defp render_inline(%MDEx.Highlight{nodes: nodes}),
    do: nodes |> render_inline() |> style([:bright])

  defp render_inline(%MDEx.Insert{nodes: nodes}), do: render_inline(nodes)
  defp render_inline(%MDEx.Superscript{nodes: nodes}), do: render_inline(nodes)

  defp render_inline(%MDEx.Link{nodes: nodes, url: url}) do
    text = render_inline(nodes)

    cond do
      url in [nil, "", text] -> style(text, [:underline])
      true -> style(text, [:underline]) <> " (" <> url <> ")"
    end
  end

  defp render_inline(%MDEx.Image{nodes: nodes, url: url}) do
    alt = nodes |> render_inline() |> String.trim()

    case {alt, url} do
      {"", ""} -> "[image]"
      {"", url} -> "[image: #{url}]"
      {alt, ""} -> "[image: #{alt}]"
      {alt, url} -> "[image: #{alt} #{url}]"
    end
  end

  defp render_inline(%MDEx.ShortCode{emoji: emoji}) when is_binary(emoji), do: emoji
  defp render_inline(%MDEx.Math{literal: literal}), do: literal
  defp render_inline(%MDEx.HtmlInline{literal: literal}), do: literal
  defp render_inline(%MDEx.Raw{literal: literal}), do: literal
  defp render_inline(%{nodes: nodes}) when is_list(nodes), do: render_inline(nodes)
  defp render_inline(node), do: node_to_text(node)

  defp node_to_text(%{literal: literal}) when is_binary(literal), do: literal
  defp node_to_text(node), do: inspect(node)

  defp join_blocks(blocks) do
    blocks
    |> reject_empty()
    |> Enum.join("\n\n")
  end

  defp reject_empty(values) do
    Enum.reject(values, fn value -> value |> IO.iodata_to_binary() |> String.trim() == "" end)
  end

  defp heading_style(1), do: [:bright, :cyan]
  defp heading_style(2), do: [:bright]
  defp heading_style(_level), do: [:bright]

  defp indent(count), do: String.duplicate(" ", count)

  defp single_line?(text), do: not String.contains?(text, "\n")

  defp style(text, codes) do
    if ansi?() do
      [IO.ANSI.format_fragment(codes, true), text, IO.ANSI.reset()] |> IO.iodata_to_binary()
    else
      text
    end
  end

  defp ansi? do
    IO.ANSI.enabled?() and System.get_env("NO_COLOR") in [nil, ""]
  end
end
