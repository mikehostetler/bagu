defmodule Jidoka.Examples.ApprovalFlow.Demo do
  @moduledoc false

  alias Jidoka.Demo.{CLI, Debug, Inventory}
  alias Jidoka.Examples.ApprovalFlow.Guardrails.RequireRefundApproval
  alias Jidoka.Examples.ApprovalFlow.Tools.SendRefund

  @spec main([String.t()]) :: :ok
  def main(argv), do: CLI.run_command(argv, "approval_flow", fn -> :ok end, &run/2)

  @spec usage() :: :ok
  def usage, do: CLI.usage("approval_flow")

  defp run(options, log_level) do
    Inventory.print_compiled("Jidoka approval flow example", agent_module(), log_level,
      notice: "Canonical example: tool guardrails produce intentional approval interrupts.",
      try: [
        ~s(mix jidoka approval_flow --verify),
        ~s(mix jidoka approval_flow --dry-run --log-level trace),
        ~s(mix jidoka approval_flow -- "Send a $750 refund for customer C-100.")
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
    assert_interrupt!()
    {:ok, refund} = SendRefund.run(%{customer_id: "C-100", amount: 750.0, approved: true}, %{})

    parsed =
      finalize!(
        ~s({"action":"send_refund","risk_level":"high","approval_required":true,) <>
          ~s("approval_reason":"Refunds of $500 or more require approval.",) <>
          ~s("result":"Refund rfnd_demo_001 was sent after approval."})
      )

    unless refund.status == :sent and parsed.approval_required do
      raise Mix.Error, message: "approval flow verification failed"
    end

    IO.puts("Approval flow verification: ok")
    IO.inspect(refund, label: "approved_tool_result")
    IO.inspect(parsed, label: "structured_output")
    :ok
  end

  defp assert_interrupt! do
    case RequireRefundApproval.call(%Jidoka.Guardrails.Tool{
           agent: nil,
           server: self(),
           request_id: "approval-flow-verify",
           tool_name: "send_refund",
           tool_call_id: "tc-refund",
           arguments: %{customer_id: "C-100", amount: 750.0, approved: false},
           context: %{notify_pid: self()},
           metadata: %{},
           request_opts: %{}
         }) do
      {:interrupt, %{kind: :approval}} -> :ok
      other -> raise Mix.Error, message: "expected approval interrupt, got: #{inspect(other)}"
    end
  end

  defp run_live(prompt, log_level) do
    CLI.ensure_api_key!()
    prompt = prompt || "Send a $750 refund for customer C-100."
    {:ok, pid} = agent_module().start_link(id: "approval-flow-live")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      result =
        agent_module().chat(pid, prompt,
          context: %{notify_pid: self(), actor: "demo-operator"},
          log_level: Debug.request_log_level(log_level)
        )

      Debug.print_recent_events(pid, log_level)
      IO.inspect(result, label: "agent")
      :ok
    after
      Debug.safe_stop_agent(pid)
    end
  end

  defp finalize!(raw) do
    request_id = "approval-flow-#{System.unique_integer([:positive])}"

    agent =
      agent_module().runtime_module().new(id: "approval-flow-verify")
      |> Jido.AI.Request.start_request(request_id, "Prepare refund.")
      |> Jido.AI.Request.complete_request(request_id, raw)
      |> Jidoka.Output.finalize(request_id, agent_module().output())

    case Jido.AI.Request.get_result(agent, request_id) do
      {:ok, parsed} -> parsed
      other -> raise Mix.Error, message: "expected parsed approval output, got: #{inspect(other)}"
    end
  end

  defp agent_module do
    Jidoka.Examples.ApprovalFlow.Agents.ApprovalAgent
  end
end
