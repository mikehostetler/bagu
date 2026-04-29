defmodule Jidoka.Examples.InvoiceExtraction.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.InvoiceExtraction.Tools.{LoadInvoice, ParseInvoice}

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "invoice_extraction", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("invoice_extraction")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka invoice extraction example", agent_module(), log_level,
      notice: "Canonical example: extract invoice fields and prove output validation failures.",
      try: [
        ~s(mix jidoka invoice_extraction --verify),
        ~s(mix jidoka invoice_extraction --dry-run --log-level trace),
        ~s(mix jidoka invoice_extraction -- "Extract invoice INV-4432.")
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
    {:ok, invoice} = LoadInvoice.run(%{invoice_id: "INV-4432"}, %{})
    {:ok, parsed_tool} = ParseInvoice.run(%{text: invoice.text}, %{})

    parsed =
      finalize!(
        ~s({"vendor":"Atlas Cloud Services","invoice_number":"INV-4432","issued_on":"2026-04-01","due_on":"2026-04-30",) <>
          ~s("line_items":[{"description":"Platform subscription","quantity":1,"amount":1200.0},{"description":"Usage overage","quantity":1,"amount":275.5}],) <>
          ~s("total":1475.5,"warnings":[]})
      )

    assert_invalid_output!()

    unless parsed.total == parsed_tool.total and length(parsed.line_items) == 2 do
      raise Mix.Error, message: "invoice extraction verification failed"
    end

    IO.puts("Invoice extraction verification: ok")
    IO.inspect(parsed_tool, label: "parsed_invoice")
    IO.inspect(parsed, label: "structured_output")
    IO.puts("Invalid output edge case: ok")
    :ok
  end

  defp assert_invalid_output! do
    request_id = "invoice-invalid-#{System.unique_integer([:positive])}"
    output = %{agent_module().output() | retries: 0, on_validation_error: :error}

    agent =
      agent_module().runtime_module().new(id: "invoice-invalid-verify")
      |> Jido.AI.Request.start_request(request_id, "Extract invoice.")
      |> Jido.AI.Request.complete_request(request_id, ~s({"vendor":"Atlas","total":"not-a-number"}))
      |> Jidoka.Output.finalize(request_id, output)

    case Jido.AI.Request.get_result(agent, request_id) do
      {:error, %Jidoka.Error.ValidationError{}} -> :ok
      other -> raise Mix.Error, message: "expected invoice validation failure, got: #{inspect(other)}"
    end
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Extract invoice INV-4432."
    {:ok, pid} = agent_module().start_link(id: "invoice-extraction-live")
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
    request_id = "invoice-extraction-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "invoice-extraction-verify")
      |> Jido.AI.Request.start_request(request_id, "Extract invoice INV-4432.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed invoice output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.InvoiceExtraction.Agents.InvoiceAgent
  end
end
