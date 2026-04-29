defmodule Mix.Tasks.Jidoka do
  use Mix.Task

  @shortdoc "Runs Jidoka demo REPLs"

  @moduledoc """
  Runs Jidoka demo agents through a Mix task.

      mix jidoka chat --dry-run
      mix jidoka imported -- "Add 17 and 25"
      mix jidoka chat --log-level debug -- "Add 17 and 25"
      mix jidoka trace --log-level trace -- 7
      mix jidoka structured_output --dry-run
      mix jidoka structured_output --dry-run -- "invalid"
      mix jidoka support_triage --verify
      mix jidoka workflow --dry-run
      mix jidoka orchestrator --log-level trace -- "Use the research_agent specialist ..."
      mix jidoka kitchen_sink --log-level trace --dry-run
  """

  @impl true
  def run(argv) do
    case argv do
      [] ->
        usage()

      ["--help"] ->
        usage()

      ["-h"] ->
        usage()

      [demo | rest] ->
        case Jidoka.Demo.preload(demo) do
          :ok ->
            _ = Mix.Task.run("app.start")

            case Jidoka.Demo.load(demo) do
              {:ok, module} -> apply(module, :main, [rest])
              {:error, message} -> raise Mix.Error, message: message
            end

          {:error, message} ->
            raise Mix.Error, message: message
        end
    end
  end

  defp usage do
    demos =
      Jidoka.Demo.names()
      |> Enum.join("|")

    Mix.shell().info("mix jidoka <#{demos}> [--log-level info|debug|trace] [--dry-run] [--verify] [prompt]")
  end
end
