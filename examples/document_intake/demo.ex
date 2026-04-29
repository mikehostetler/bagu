defmodule Jidoka.Examples.DocumentIntake.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.DocumentIntake.Tools.{LoadDocument, RouteDocument}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "document_intake", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("document_intake")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka document intake example", agent_module(), log_level,
      notice: "Canonical example: classify, extract, and route mixed operational documents.",
      try: [
        ~s(mix jidoka document_intake --verify),
        ~s(mix jidoka document_intake --dry-run --log-level trace),
        ~s(mix jidoka document_intake -- "Route document DOC-INV.")
      ]
    )

    CLI.print_log_status(log_level)

    cond do
      options.dry_run? -> IO.puts("Dry run: no agent started.")
      options.verify? -> verify!()
      true -> run_live(options.prompt, log_level)
    end
  end

  defp verify! do
    routes =
      ["DOC-INV", "DOC-LEGAL", "DOC-SUPPORT"]
      |> Enum.map(fn id ->
        {:ok, document} = LoadDocument.run(%{document_id: id}, %{})
        {:ok, route} = RouteDocument.run(%{text: document.text}, %{})
        {id, route}
      end)

    parsed =
      finalize!(
        ~s({"document_type":"invoice","route":"finance_ops","confidence":0.97,) <>
          ~s("summary":"Atlas Cloud Services invoice for $1475.50.",) <>
          ~s("extracted_fields":{"invoice_number":"INV-4432","vendor":"Atlas Cloud Services","amount":1475.50}})
      )

    unless Enum.map(routes, fn {_id, route} -> route.route end) == [:finance_ops, :legal_ops, :support_ops] and
             parsed.route == :finance_ops do
      raise Mix.Error, message: "document intake verification failed"
    end

    IO.puts("Document intake verification: ok")
    IO.inspect(routes, label: "routes")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Route document DOC-INV."
    {:ok, pid} = agent_module().start_link(id: "document-intake-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result = agent_module().chat(pid, prompt, log_level: Debug.request_log_level(log_level))
      Debug.print_recent_events(pid, log_level)
      IO.inspect(result, label: "agent")
      :ok
    after
      Debug.safe_stop_agent(pid)
    end
  end

  defp finalize!(raw) do
    request_id = "document-intake-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "document-intake-verify")
      |> Jido.AI.Request.start_request(request_id, "Route document DOC-INV.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed document output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.DocumentIntake.Agents.IntakeAgent
  end
end
