defmodule MotoTest.InjectTenantHook do
  use Moto.Hook, name: "inject_tenant"

  @impl true
  def call(%Moto.Hooks.BeforeTurn{} = input) do
    sequence = Map.get(input.metadata, :sequence, [])

    {:ok,
     %{
       message: "#{input.message} for acme",
       context: %{tenant: "acme"},
       allowed_tools: ["add_numbers"],
       llm_opts: [temperature: 0.1],
       metadata: %{sequence: sequence ++ ["inject_tenant"], touched?: true}
     }}
  end
end

defmodule MotoTest.RestrictRefundsHook do
  use Moto.Hook, name: "restrict_refunds"

  @impl true
  def call(%Moto.Hooks.BeforeTurn{} = input) do
    sequence = Map.get(input.metadata, :sequence, [])
    {:ok, %{metadata: %{sequence: sequence ++ ["restrict_refunds"], mode: :refunds}}}
  end
end

defmodule MotoTest.NormalizeReplyHook do
  use Moto.Hook, name: "normalize_reply"

  @impl true
  def call(%Moto.Hooks.AfterTurn{outcome: {:ok, result}}) do
    {:ok, {:ok, "normalized:#{result}"}}
  end

  def call(%Moto.Hooks.AfterTurn{outcome: {:error, reason}}) do
    {:ok, {:error, {:normalized_error, reason}}}
  end
end

defmodule MotoTest.InterruptBeforeHook do
  use Moto.Hook, name: "approval_gate"

  @impl true
  def call(%Moto.Hooks.BeforeTurn{} = input) do
    notify_pid = Map.get(input.context, :notify_pid, Map.get(input.context, "notify_pid"))

    {:interrupt,
     %{
       kind: :approval,
       message: "Approval required",
       data: %{notify_pid: notify_pid, from: :before_turn}
     }}
  end
end

defmodule MotoTest.InterruptAfterHook do
  use Moto.Hook, name: "interrupt_after_turn"

  @impl true
  def call(%Moto.Hooks.AfterTurn{} = input) do
    notify_pid = Map.get(input.context, :notify_pid, Map.get(input.context, "notify_pid"))

    {:interrupt,
     %{
       kind: :review,
       message: "Review required",
       data: %{notify_pid: notify_pid, from: :after_turn}
     }}
  end
end

defmodule MotoTest.NotifyOpsHook do
  use Moto.Hook, name: "notify_ops"

  @impl true
  def call(%Moto.Hooks.InterruptInput{interrupt: interrupt}) do
    if pid = get_in(interrupt.data, [:notify_pid]) do
      send(pid, {:hook_interrupt, interrupt.kind, interrupt.data[:from]})
    end

    :ok
  end
end

defmodule MotoTest.HookCallbacks do
  def before_turn(%Moto.Hooks.BeforeTurn{} = input, label) do
    sequence = Map.get(input.metadata, :sequence, [])
    {:ok, %{metadata: %{sequence: sequence ++ [label]}}}
  end

  def after_turn(%Moto.Hooks.AfterTurn{outcome: {:ok, result}}, suffix) do
    {:ok, {:ok, "#{result}#{suffix}"}}
  end

  def after_turn(%Moto.Hooks.AfterTurn{outcome: {:error, reason}}, suffix) do
    {:ok, {:error, {suffix, reason}}}
  end

  def notify_interrupt(%Moto.Hooks.InterruptInput{interrupt: interrupt}, label) do
    if pid = get_in(interrupt.data, [:notify_pid]) do
      send(pid, {:hook_interrupt_callback, label, interrupt.kind})
    end

    :ok
  end
end

defmodule MotoTest.SafePromptGuardrail do
  use Moto.Guardrail, name: "safe_prompt"

  @impl true
  def call(%Moto.Guardrails.Input{message: message}) do
    if String.contains?(String.downcase(message), "secret") do
      {:error, :unsafe_prompt}
    else
      :ok
    end
  end
end

defmodule MotoTest.SafeReplyGuardrail do
  use Moto.Guardrail, name: "safe_reply"

  @impl true
  def call(%Moto.Guardrails.Output{outcome: {:ok, result}}) when is_binary(result) do
    if String.contains?(String.downcase(result), "unsafe") do
      {:error, :unsafe_reply}
    else
      :ok
    end
  end

  def call(%Moto.Guardrails.Output{}), do: :ok
end

defmodule MotoTest.ApproveLargeMathToolGuardrail do
  use Moto.Guardrail, name: "approve_large_math_tool"

  @impl true
  def call(%Moto.Guardrails.Tool{
        tool_name: "add_numbers",
        arguments: arguments,
        context: context
      }) do
    a = Map.get(arguments, :a, Map.get(arguments, "a", 0))
    b = Map.get(arguments, :b, Map.get(arguments, "b", 0))

    if a + b > 40 do
      notify_pid = Map.get(context, :notify_pid, Map.get(context, "notify_pid"))

      {:interrupt,
       %{
         kind: :approval,
         message: "Large calculations require approval",
         data: %{notify_pid: notify_pid, from: :tool_guardrail}
       }}
    else
      :ok
    end
  end

  def call(%Moto.Guardrails.Tool{}), do: :ok
end

defmodule MotoTest.GuardrailCallbacks do
  def input(%Moto.Guardrails.Input{} = input, label) do
    sequence = Map.get(input.metadata, :sequence, [])

    if String.contains?(input.message, "blocked_by_#{label}") do
      {:error, {:blocked, label}}
    else
      {:error, {:input_callback, sequence ++ [label]}}
    end
  end

  def output(%Moto.Guardrails.Output{}, label), do: {:error, {:output_callback, label}}
  def tool(%Moto.Guardrails.Tool{}, label), do: {:error, {:tool_callback, label}}
end

defmodule MotoTest.HookedAgent do
  use Moto.Agent

  agent do
    id :hooked_agent
  end

  defaults do
    model :fast
    instructions "You have hooks."
  end

  lifecycle do
    before_turn MotoTest.InjectTenantHook
    before_turn {MotoTest.HookCallbacks, :before_turn, ["dsl_mfa"]}
    after_turn MotoTest.NormalizeReplyHook
    after_turn {MotoTest.HookCallbacks, :after_turn, ["!"]}
    on_interrupt MotoTest.NotifyOpsHook
    on_interrupt {MotoTest.HookCallbacks, :notify_interrupt, ["dsl_mfa"]}
  end
end

defmodule MotoTest.GuardrailedAgent do
  use Moto.Agent

  agent do
    id :guardrailed_agent
  end

  defaults do
    model :fast
    instructions "You enforce guardrails."
  end

  capabilities do
    tool MotoTest.AddNumbers
  end

  lifecycle do
    on_interrupt MotoTest.NotifyOpsHook

    input_guardrail MotoTest.SafePromptGuardrail
    output_guardrail MotoTest.SafeReplyGuardrail
    tool_guardrail MotoTest.ApproveLargeMathToolGuardrail
  end
end

defmodule MotoTest.InterruptingAgent do
  use Moto.Agent

  agent do
    id :interrupting_agent
  end

  defaults do
    model :fast
    instructions "You may interrupt."
  end

  lifecycle do
    before_turn MotoTest.InterruptBeforeHook
    on_interrupt MotoTest.NotifyOpsHook
  end
end
