defmodule Jidoka.Examples.StructuredOutput.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Inventory}

  @spec main([String.t()]) :: :ok
  def main(argv) do
    CLI.run_command(argv, "structured_output", fn -> :ok end, &run/2)
  end

  @spec usage() :: :ok
  def usage, do: CLI.usage("structured_output")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka structured output demo", agent_module(), log_level,
      notice: "This demo is deterministic; it does not call a provider.",
      try: [
        ~s(mix jidoka structured_output --dry-run),
        ~s(mix jidoka structured_output --dry-run -- "invalid"),
        ~s(mix jidoka structured_output --dry-run -- "repair-invalid")
      ]
    )

    CLI.print_log_status(log_level)

    case mode(options.prompt) do
      :valid -> run_valid!()
      :invalid -> run_invalid!()
      :repair_invalid -> run_repair_invalid!()
    end

    :ok
  end

  defp run_valid! do
    request_id = "structured-output-smoke-#{System.unique_integer([:positive])}"
    runtime = agent_module().runtime_module()

    {:ok, agent, {:ai_react_start, params}} =
      runtime.on_before_cmd(
        runtime.new(id: "structured-output-smoke-agent"),
        {:ai_react_start,
         %{
           query: "I was double charged for my last invoice.",
           request_id: request_id,
           tool_context: %{}
         }}
      )

    agent =
      agent
      |> Jido.AI.Request.start_request(request_id, "I was double charged for my last invoice.")
      |> Jido.AI.Request.complete_request(
        request_id,
        ~s({"category":"billing","confidence":0.97,"summary":"Customer reports a duplicate invoice charge."})
      )

    {:ok, finalized, []} = runtime.on_after_cmd(agent, {:ai_react_start, params}, [])

    assert_result!(
      Jido.AI.Request.get_result(finalized, request_id),
      fn parsed ->
        parsed.category == :billing and is_float(parsed.confidence) and is_binary(parsed.summary)
      end,
      "expected parsed billing output"
    )

    IO.puts("Structured output verification: ok")
    IO.inspect(Jido.AI.Request.get_result(finalized, request_id), label: "result")
    IO.inspect(get_in(finalized.state, [:requests, request_id, :meta, :jidoka_output]), label: "output meta")
  end

  defp run_invalid! do
    request_id = "structured-output-invalid-#{System.unique_integer([:positive])}"
    output = %{agent_module().output() | retries: 0, on_validation_error: :error}

    agent =
      runtime_agent("structured-output-invalid-agent")
      |> Jido.AI.Request.start_request(request_id, "Classify this.")
      |> Jido.AI.Request.complete_request(
        request_id,
        ~s({"category":"legal","confidence":"very","extra":"surprise"})
      )
      |> Jidoka.Output.finalize(request_id, output)

    assert_error!(Jido.AI.Request.get_result(agent, request_id), "expected invalid output to fail")

    IO.puts("Structured output edge verification: failed as expected")
    IO.inspect(Jido.AI.Request.get_result(agent, request_id), label: "result")
    IO.puts("formatted error: #{Jidoka.format_error(get_in(agent.state, [:requests, request_id, :error]))}")
  end

  defp run_repair_invalid! do
    request_id = "structured-output-repair-invalid-#{System.unique_integer([:positive])}"

    repair_fun = fn _output, _agent, _context, _raw, _reason ->
      {:ok, %{category: :legal, confidence: "high"}}
    end

    agent =
      runtime_agent("structured-output-repair-invalid-agent")
      |> Jido.AI.Request.start_request(request_id, "Classify this.")
      |> Jido.AI.Request.complete_request(request_id, "not parseable")
      |> Jidoka.Output.finalize(request_id, agent_module().output(), repair_fun: repair_fun)

    assert_error!(Jido.AI.Request.get_result(agent, request_id), "expected invalid repair output to fail")

    IO.puts("Structured output repair edge verification: failed as expected")
    IO.inspect(Jido.AI.Request.get_result(agent, request_id), label: "result")
    IO.inspect(get_in(agent.state, [:requests, request_id, :meta, :jidoka_output]), label: "output meta")
  end

  defp mode(nil), do: :valid

  defp mode(prompt) do
    prompt = String.downcase(prompt)

    cond do
      String.contains?(prompt, "repair") -> :repair_invalid
      String.contains?(prompt, "invalid") or String.contains?(prompt, "break") -> :invalid
      true -> :valid
    end
  end

  defp assert_result!({:ok, parsed}, predicate, _message) when is_function(predicate, 1) do
    if predicate.(parsed), do: :ok, else: raise(Mix.Error, message: "structured output verification failed")
  end

  defp assert_result!(other, _predicate, message) do
    raise Mix.Error, message: "#{message}: #{inspect(other)}"
  end

  defp assert_error!({:error, %Jidoka.Error.ValidationError{}}, _message), do: :ok

  defp assert_error!(other, message) do
    raise Mix.Error, message: "#{message}: #{inspect(other)}"
  end

  defp runtime_agent(id) do
    agent_module().runtime_module().new(id: id)
  end

  defp agent_module do
    Jidoka.Examples.StructuredOutput.Agents.TicketClassifier
  end
end
