defmodule Moto.Demo.CLI do
  @moduledoc false

  alias Moto.Demo.Debug

  @switches [log_level: :string, dry_run: :boolean, help: :boolean]
  @aliases [l: :log_level]

  @type options :: %{
          help?: boolean(),
          log_level: Debug.log_level(),
          dry_run?: boolean(),
          prompt: String.t() | nil
        }

  @spec parse([String.t()]) :: {:ok, options()} | {:error, String.t()}
  def parse(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] ->
        {:error, "invalid options: #{Enum.map_join(invalid, ", ", fn {key, _} -> "--#{key}" end)}"}

      opts[:help] ->
        {:ok, %{help?: true, log_level: :info, dry_run?: false, prompt: nil}}

      true ->
        with {:ok, log_level} <- Debug.parse_log_level(opts) do
          {:ok,
           %{
             help?: false,
             log_level: log_level,
             dry_run?: Keyword.get(opts, :dry_run, false),
             prompt: join_prompt(normalize_argv(args))
           }}
        end
    end
  end

  @spec usage(String.t()) :: :ok
  def usage(command) when is_binary(command) do
    IO.puts("mix moto #{command} [--log-level info|debug|trace] [--dry-run] [prompt]")
    :ok
  end

  @spec print_log_status(Debug.log_level()) :: :ok
  def print_log_status(log_level) do
    Debug.print_status(log_level)
    Debug.print_trace_status(log_level)
  end

  @spec with_started_agent(
          options(),
          Debug.log_level(),
          (-> {:ok, pid()}),
          function(),
          function()
        ) ::
          :ok
  def with_started_agent(options, log_level, start_fun, interactive_fun, one_shot_fun)
      when is_function(start_fun, 0) and is_function(interactive_fun, 2) and
             is_function(one_shot_fun, 3) do
    if options.dry_run? do
      IO.puts("Dry run: no agent started.")
      :ok
    else
      ensure_api_key!()
      {:ok, pid} = start_fun.()
      Debug.maybe_enable_agent_debug(pid, log_level)

      try do
        if options.prompt == nil do
          interactive_fun.(pid, log_level)
        else
          one_shot_fun.(pid, options.prompt, log_level)
        end
      after
        Debug.safe_stop_agent(pid)
      end
    end
  end

  @spec ensure_api_key!() :: :ok | no_return()
  def ensure_api_key! do
    anthropic_api_key = Application.get_env(:req_llm, :anthropic_api_key)

    if is_nil(anthropic_api_key) or anthropic_api_key == "" do
      IO.puts("ANTHROPIC_API_KEY is not configured.")
      IO.puts("Add it to .env or export it in your shell.")
      System.halt(1)
    end

    :ok
  end

  @spec join_prompt([String.t()]) :: String.t() | nil
  def join_prompt([]), do: nil
  def join_prompt(args), do: Enum.join(args, " ")

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv
end
