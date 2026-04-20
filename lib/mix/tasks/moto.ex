defmodule Mix.Tasks.Moto do
  use Mix.Task

  @shortdoc "Runs Moto demo REPLs"

  @moduledoc """
  Runs Moto demo agents through a Mix task.

      mix moto chat --dry-run
      mix moto chat --log-level debug -- "Add 17 and 25"
      mix moto orchestrator --log-level trace -- "Use the research_agent specialist ..."
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    case argv do
      [] ->
        usage()

      ["chat" | rest] ->
        Moto.Demo.ChatCLI.main(rest)

      ["orchestrator" | rest] ->
        Moto.Demo.OrchestratorCLI.main(rest)

      ["--help"] ->
        usage()

      ["-h"] ->
        usage()

      [other | _rest] ->
        raise Mix.Error,
          message: "unknown demo #{inspect(other)}. Expected `chat` or `orchestrator`."
    end
  end

  defp usage do
    Mix.shell().info(
      "mix moto <chat|orchestrator> [--log-level info|debug|trace] [--dry-run] [prompt]"
    )
  end
end
