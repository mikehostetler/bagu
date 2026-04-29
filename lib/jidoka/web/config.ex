defmodule Jidoka.Web.Config do
  @moduledoc false

  @max_results 5
  @max_content_chars 12_000

  @spec max_results() :: pos_integer()
  def max_results, do: @max_results

  @spec max_content_chars() :: pos_integer()
  def max_content_chars, do: @max_content_chars
end
