defmodule Mix.Tasks.Moto do
  use Mix.Task

  @shortdoc "Runs Moto demo REPLs"

  @moduledoc """
  Runs Moto demo agents through a Mix task.

      mix moto chat --dry-run
      mix moto imported -- "Add 17 and 25"
      mix moto chat --log-level debug -- "Add 17 and 25"
      mix moto workflow --dry-run
      mix moto orchestrator --log-level trace -- "Use the research_agent specialist ..."
      mix moto kitchen_sink --log-level trace --dry-run
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    case argv do
      [] ->
        usage()

      ["chat" | rest] ->
        Moto.Demo.ChatCLI.main(rest)

      ["imported" | rest] ->
        Moto.Demo.ImportedChatCLI.main(rest)

      ["orchestrator" | rest] ->
        Moto.Demo.OrchestratorCLI.main(rest)

      ["workflow" | rest] ->
        Moto.Demo.WorkflowCLI.main(rest)

      ["kitchen_sink" | rest] ->
        Moto.Demo.KitchenSinkCLI.main(rest)

      ["--help"] ->
        usage()

      ["-h"] ->
        usage()

      [other | _rest] ->
        raise Mix.Error,
          message:
            "unknown demo #{inspect(other)}. Expected `chat`, `imported`, `workflow`, `orchestrator`, or `kitchen_sink`."
    end
  end

  defp usage do
    Mix.shell().info(
      "mix moto <chat|imported|workflow|orchestrator|kitchen_sink> [--log-level info|debug|trace] [--dry-run] [prompt]"
    )
  end
end
