defmodule Jidoka.Output.Config do
  @moduledoc false

  @context_key :__jidoka_output__
  @max_retries 3
  @default_retries 1
  @default_on_validation_error :repair
  @raw_preview_bytes 500

  @spec context_key() :: atom()
  def context_key, do: @context_key

  @spec max_retries() :: non_neg_integer()
  def max_retries, do: @max_retries

  @spec default_retries() :: non_neg_integer()
  def default_retries, do: @default_retries

  @spec default_on_validation_error() :: :repair
  def default_on_validation_error, do: @default_on_validation_error

  @spec raw_preview_bytes() :: pos_integer()
  def raw_preview_bytes, do: @raw_preview_bytes
end
