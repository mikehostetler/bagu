defmodule Moto.Demo.WorkflowCLI do
  @moduledoc false

  alias Moto.Demo.{CLI, Debug, Loader}

  @spec main([String.t()]) :: :ok
  def main(argv) do
    Loader.load!(:workflow)

    case CLI.parse(argv) do
      {:ok, %{help?: true}} ->
        usage()

      {:ok, options} ->
        Debug.with_log_level(options.log_level, fn log_level ->
          run(options, log_level)
        end)

      {:error, message} ->
        raise Mix.Error, message: message
    end
  end

  @spec usage() :: :ok
  def usage, do: CLI.usage("workflow")

  defp run(options, log_level) do
    print_header(log_level)
    CLI.print_log_status(log_level)

    if options.dry_run? do
      IO.puts("Dry run: workflow not executed.")
    else
      value = parse_value!(options.prompt || "5")

      case workflow_module().run(%{value: value}, return: :debug) do
        {:ok, debug} ->
          IO.puts("workflow> input=#{value} output=#{inspect(debug.output)}")
          IO.puts("workflow> steps=#{inspect(debug.steps)}")

        {:error, reason} ->
          IO.puts("error> #{Moto.format_error(reason)}")
      end
    end

    :ok
  end

  defp print_header(log_level) do
    {:ok, inspection} = Moto.inspect_workflow(workflow_module())

    IO.puts("Moto workflow demo")
    IO.puts("Workflow: #{inspection.id}")
    IO.puts("Steps: #{Enum.map_join(inspection.steps, ", ", &Atom.to_string(&1.name))}")

    if log_level == :trace do
      IO.puts("Dependencies: #{inspect(inspection.dependencies)}")
      IO.puts("Output: #{inspect(inspection.output)}")
    end

    IO.puts("")
  end

  defp parse_value!(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {integer, ""} ->
        integer

      _other ->
        raise Mix.Error, message: "workflow demo expects an integer input, got: #{inspect(value)}"
    end
  end

  defp workflow_module do
    Module.concat([Moto, Examples, Workflow, Workflows, MathPipeline])
  end
end
