defmodule Bagu.Examples.Support.Demo do
  @moduledoc false

  alias Bagu.Demo.{AgentSession, CLI, Debug, Inventory, Markdown}

  @spec main([String.t()]) :: :ok
  def main(argv) do
    CLI.run_command(argv, "support", fn -> :ok end, &run/2)
  end

  @spec usage() :: :ok
  def usage, do: CLI.usage("support")

  defp run(options, log_level) do
    print_header(log_level)
    CLI.print_log_status(log_level)

    cond do
      options.dry_run? ->
        IO.puts("Dry run: no agent started and no workflow executed.")

      options.prompt == nil ->
        run_interactive(log_level)

      true ->
        run_input(options.prompt, log_level)
    end
  end

  defp run_interactive(log_level) do
    CLI.ensure_api_key!()
    {:ok, pid} = agent_module().start_link(id: "script-support-agent")
    Debug.maybe_enable_agent_debug(pid, log_level)

    try do
      print_repl_intro()
      repl(pid, log_level)
    after
      Debug.safe_stop_agent(pid)
    end
  end

  defp run_input(prompt, log_level) do
    case parse_prompt(prompt) do
      {:chat, message} ->
        CLI.ensure_api_key!()
        {:ok, pid} = agent_module().start_link(id: "script-support-agent")
        Debug.maybe_enable_agent_debug(pid, log_level)

        try do
          AgentSession.one_shot(pid, message, log_level, session_opts())
        after
          Debug.safe_stop_agent(pid)
        end

      {:workflow, module, input} ->
        if workflow_requires_api_key?(module), do: CLI.ensure_api_key!()
        run_workflow(module, input, log_level)

      {:help, text} ->
        IO.puts(text)
    end
  end

  defp repl(pid, log_level) do
    case IO.gets("support> ") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      input ->
        prompt = String.trim(input)

        cond do
          prompt == "" ->
            repl(pid, log_level)

          prompt in ["exit", "quit"] ->
            :ok

          true ->
            IO.puts("")
            dispatch_repl(pid, prompt, log_level)
            IO.puts("")
            repl(pid, log_level)
        end
    end
  end

  defp dispatch_repl(pid, prompt, log_level) do
    case parse_prompt(prompt) do
      {:chat, message} ->
        AgentSession.one_shot(pid, message, log_level, session_opts())

      {:workflow, module, input} ->
        run_workflow(module, input, log_level)

      {:help, text} ->
        IO.puts(text)
    end
  end

  defp run_workflow(module, input, log_level) do
    opts = if log_level == :trace, do: [return: :debug], else: []

    case module.run(input, opts) do
      {:ok, %{workflow_id: workflow_id, output: output, steps: steps}} ->
        IO.puts("workflow> #{workflow_id} output=#{inspect(output)}")
        IO.puts("workflow> steps=#{inspect(steps)}")

      {:ok, output} ->
        Markdown.print_reply("workflow", inspect(output))

      {:error, reason} ->
        IO.puts("error> #{Bagu.format_error(reason)}")
    end
  end

  defp print_header(log_level) do
    Inventory.print_compiled("Bagu support demo", agent_module(), log_level,
      notice: "This example keeps the boundary explicit: chat agents coordinate, workflows run fixed processes.",
      try: [
        ~s(mix bagu support -- "Customer acct_vip says order ord_damaged arrived broken and wants a refund because it was damaged on arrival."),
        ~s(mix bagu support -- "/refund acct_vip ord_damaged Damaged on arrival"),
        ~s(mix bagu support -- "/escalate acct_trial Customer is locked out and threatening to cancel")
      ]
    )

    IO.puts("Deterministic workflows")

    Enum.each(workflow_summaries(), fn {purpose, module} ->
      {:ok, inspection} = Bagu.inspect_workflow(module)
      step_line = Enum.map_join(inspection.steps, " -> ", &format_step/1)
      IO.puts("  #{inspection.id}  #{purpose}")
      IO.puts("    steps: #{step_line}")

      if log_level == :trace do
        IO.puts("    dependencies: #{inspect(inspection.dependencies)}")
      end
    end)

    IO.puts("")
    IO.puts("Boundary")
    IO.puts("  chat agent: open-ended intake and delegation across specialist teammates")
    IO.puts("  workflow capability: review_refund lets the agent run a fixed refund process")
    IO.puts("  workflows: app-owned support processes with fixed step order")
    IO.puts("  escalation_draft: deterministic flow that reuses writer_specialist as one bounded step")
    IO.puts("")
  end

  defp print_repl_intro do
    IO.puts("Type `exit` or press Ctrl-D to quit.")
    IO.puts("Plain text goes to the support chat agent.")
    IO.puts("Slash commands run workflows directly:")
    IO.puts("  /refund <account_id> <order_id> <reason>")
    IO.puts("  /escalate <account_id> <issue>")
    IO.puts("  /help")
    IO.puts("")
  end

  defp parse_prompt("/refund " <> rest) do
    case String.split(rest, " ", parts: 3, trim: true) do
      [account_id, order_id, reason] ->
        {:workflow, refund_workflow_module(), %{account_id: account_id, order_id: order_id, reason: reason}}

      _other ->
        {:help, "usage> /refund <account_id> <order_id> <reason>"}
    end
  end

  defp parse_prompt("/escalate " <> rest) do
    case String.split(rest, " ", parts: 2, trim: true) do
      [account_id, issue] ->
        {:workflow, escalation_workflow_module(), %{account_id: account_id, issue: issue}}

      _other ->
        {:help, "usage> /escalate <account_id> <issue>"}
    end
  end

  defp parse_prompt("/help"), do: {:help, "/refund, /escalate, or a plain-text support prompt"}
  defp parse_prompt(prompt), do: {:chat, prompt}

  defp session_opts do
    [
      reply_label: "support",
      interactive_reply_label: "support",
      try: [
        "Customer acct_vip says order ord_damaged arrived broken and wants a refund because it was damaged on arrival.",
        "Please rewrite this reply to sound calmer and more direct."
      ],
      subagents: [empty: :silent, result_preview?: true],
      chat: fn pid, prompt, level, mode ->
        session = if mode == :interactive, do: "support-repl", else: "support-cli"

        agent_module().chat(pid, prompt,
          context: %{channel: "support_chat", session: session},
          log_level: Debug.request_log_level(level)
        )
      end
    ]
  end

  defp workflow_summaries do
    [
      {"tool-only refund policy process", refund_workflow_module()},
      {"deterministic escalation flow with a writer agent step", escalation_workflow_module()}
    ]
  end

  defp format_step(%{name: name, kind: kind, target: target}) do
    "#{name}(#{kind}:#{format_target(target)})"
  end

  defp format_target(target) when is_atom(target) do
    target
    |> Module.split()
    |> List.last()
  end

  defp format_target(target), do: inspect(target)

  defp workflow_requires_api_key?(module), do: module == escalation_workflow_module()

  defp agent_module do
    Module.concat([Bagu, Examples, Support, Agents, SupportRouterAgent])
  end

  defp refund_workflow_module do
    Module.concat([Bagu, Examples, Support, Workflows, RefundReview])
  end

  defp escalation_workflow_module do
    Module.concat([Bagu, Examples, Support, Workflows, EscalationDraft])
  end
end
