defmodule Moto.Guardrails do
  @moduledoc false

  alias Jido.AI.Request
  alias Moto.Interrupt

  @request_guardrails_key :__moto_guardrails__
  @tool_guardrail_callback_key :__tool_guardrail_callback__
  @stages [:input, :output, :tool]
  @guardrail_timeout_ms 5_000

  defmodule Input do
    @moduledoc false
    @enforce_keys [
      :agent,
      :server,
      :request_id,
      :message,
      :context,
      :allowed_tools,
      :llm_opts,
      :metadata,
      :request_opts
    ]
    defstruct [
      :agent,
      :server,
      :request_id,
      :message,
      :context,
      :allowed_tools,
      :llm_opts,
      :metadata,
      :request_opts
    ]
  end

  defmodule Output do
    @moduledoc false
    @enforce_keys [
      :agent,
      :server,
      :request_id,
      :message,
      :context,
      :allowed_tools,
      :llm_opts,
      :metadata,
      :request_opts,
      :outcome
    ]
    defstruct [
      :agent,
      :server,
      :request_id,
      :message,
      :context,
      :allowed_tools,
      :llm_opts,
      :metadata,
      :request_opts,
      :outcome
    ]
  end

  defmodule Tool do
    @moduledoc false
    @enforce_keys [
      :agent,
      :server,
      :request_id,
      :tool_name,
      :arguments,
      :context,
      :metadata,
      :request_opts
    ]
    defstruct [
      :agent,
      :server,
      :request_id,
      :tool_name,
      :tool_call_id,
      :arguments,
      :context,
      :metadata,
      :request_opts
    ]
  end

  @type stage :: :input | :output | :tool
  @type guardrail_ref ::
          module()
          | {module(), atom(), [term()]}
          | (term() -> :ok | {:error, term()} | {:interrupt, term()})
  @type stage_map :: %{
          input: [guardrail_ref()],
          output: [guardrail_ref()],
          tool: [guardrail_ref()]
        }

  @spec default_stage_map() :: stage_map()
  def default_stage_map do
    Moto.StageRefs.default_stage_map(@stages)
  end

  @spec normalize_dsl_guardrails(stage_map()) :: {:ok, stage_map()} | {:error, String.t()}
  def normalize_dsl_guardrails(guardrails) when is_map(guardrails) do
    Moto.StageRefs.normalize_dsl(guardrails, stage_ref_opts())
  end

  @spec normalize_request_guardrails(term()) :: {:ok, stage_map()} | {:error, term()}
  def normalize_request_guardrails(guardrails),
    do: Moto.StageRefs.normalize_request(guardrails, stage_ref_opts())

  @spec validate_dsl_guardrail_ref(stage(), term()) :: :ok | {:error, String.t()}
  def validate_dsl_guardrail_ref(stage, ref) when stage in @stages do
    Moto.StageRefs.validate_dsl_ref(stage, ref, stage_ref_opts())
  end

  @spec attach_request_guardrails(map(), stage_map()) :: map()
  def attach_request_guardrails(context, guardrails)
      when is_map(context) and is_map(guardrails) do
    maybe_attach_request_guardrails(context, guardrails)
  end

  @spec on_before_cmd(Jido.Agent.t(), term(), stage_map()) :: {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(agent, {:ai_react_start, %{query: query} = params}, defaults) do
    request_id = params[:request_id] || agent.state[:last_request_id]
    {request_guardrails, params} = pop_request_guardrails(params)
    guardrails = combine(defaults, request_guardrails)
    context = Map.get(params, :tool_context, %{}) || %{}

    input = %Input{
      agent: agent,
      server: self(),
      request_id: request_id,
      message: query,
      context: context,
      allowed_tools: Map.get(params, :allowed_tools),
      llm_opts: Map.get(params, :llm_opts, []),
      metadata: %{},
      request_opts: params
    }

    guardrail_meta = %{
      guardrails: guardrails,
      message: input.message,
      context: input.context,
      allowed_tools: input.allowed_tools,
      llm_opts: input.llm_opts,
      request_opts: input.request_opts,
      metadata: input.metadata
    }

    case run_input(guardrails.input, input) do
      :ok ->
        params =
          Map.update(params, :tool_context, %{}, fn tool_context ->
            tool_context
            |> Kernel.||(%{})
            |> maybe_attach_tool_guardrail_callback(guardrails.tool, agent, request_id)
          end)

        {:ok, put_request_guardrail_meta(agent, request_id, guardrail_meta), {:ai_react_start, params}}

      {:error, label, reason} ->
        error = normalize_guardrail_error(:input, label, reason, agent, request_id)

        agent =
          agent
          |> Request.fail_request(request_id, error)
          |> put_request_guardrail_meta(request_id, Map.put(guardrail_meta, :error, error))

        {:ok, agent, {:ai_react_request_error, %{request_id: request_id, reason: :guardrail_blocked, message: query}}}

      {:interrupt, label, %Interrupt{} = interrupt} ->
        agent =
          agent
          |> Request.fail_request(request_id, {:interrupt, interrupt})
          |> put_request_guardrail_meta(
            request_id,
            guardrail_meta
            |> Map.put(:interrupt, interrupt)
            |> Map.put(:interrupt_guardrail, label)
          )

        Moto.Hooks.notify_interrupt(agent, request_id, interrupt)

        {:ok, agent, {:ai_react_request_error, %{request_id: request_id, reason: :interrupt, message: query}}}
    end
  end

  def on_before_cmd(agent, action, _defaults), do: {:ok, agent, action}

  @spec on_after_cmd(Jido.Agent.t(), term(), [term()], stage_map()) ::
          {:ok, Jido.Agent.t(), [term()]}
  def on_after_cmd(agent, {:ai_react_start, %{request_id: request_id}}, directives, _defaults) do
    run_output_guardrails(agent, request_id, directives)
  end

  def on_after_cmd(agent, _action, directives, _defaults) do
    run_output_guardrails(agent, agent.state[:last_request_id], directives)
  end

  @spec combine(stage_map(), stage_map()) :: stage_map()
  def combine(defaults, request_guardrails) do
    Moto.StageRefs.combine(@stages, defaults, request_guardrails)
  end

  defp stage_ref_opts do
    [
      stages: @stages,
      spec_label: "guardrails",
      ref_label: "guardrail",
      invalid_stage: :invalid_guardrail_stage,
      invalid_spec: :invalid_guardrail_spec,
      invalid_ref: :invalid_guardrail,
      module_validator: &Moto.Guardrail.validate_guardrail_module/1,
      dsl_function_error:
        "DSL guardrails do not support anonymous functions; use a Moto.Guardrail module or MFA instead",
      invalid_ref_message: fn other ->
        "guardrail refs must be a Moto.Guardrail module, MFA tuple, or runtime function, got: #{inspect(other)}"
      end
    ]
  end

  defp maybe_attach_request_guardrails(context, guardrails) do
    if guardrails == default_stage_map() do
      context
    else
      Map.put(context, @request_guardrails_key, guardrails)
    end
  end

  defp pop_request_guardrails(params) when is_map(params) do
    context = Map.get(params, :tool_context, %{}) || %{}
    {request_guardrails, context} = Map.pop(context, @request_guardrails_key, default_stage_map())
    {request_guardrails, Map.put(params, :tool_context, context)}
  end

  defp maybe_attach_tool_guardrail_callback(context, [], _agent, _request_id), do: context

  defp maybe_attach_tool_guardrail_callback(context, tool_guardrails, agent, request_id)
       when is_map(context) and is_binary(request_id) do
    callback = fn %{
                    tool_name: tool_name,
                    tool_call_id: tool_call_id,
                    arguments: arguments,
                    context: runtime_context
                  } ->
      input = %Tool{
        agent: agent,
        server: self(),
        request_id: request_id,
        tool_name: tool_name,
        tool_call_id: tool_call_id,
        arguments: arguments,
        context: runtime_context,
        metadata: %{},
        request_opts: %{}
      }

      case run_guardrails(tool_guardrails, input) do
        :ok ->
          :ok

        {:error, label, reason} ->
          {:error, normalize_guardrail_error(:tool, label, reason, agent, request_id)}

        {:interrupt, _label, %Interrupt{} = interrupt} ->
          Moto.Hooks.notify_interrupt(agent, request_id, interrupt)
          {:interrupt, interrupt}
      end
    end

    Map.put(context, @tool_guardrail_callback_key, callback)
  end

  defp maybe_attach_tool_guardrail_callback(context, _tool_guardrails, _agent, _request_id),
    do: context

  defp run_input(guardrails, %Input{} = input) do
    run_guardrails(guardrails, input)
  end

  defp run_output(guardrails, %Output{} = input) do
    run_guardrails(guardrails, input)
  end

  defp run_guardrails(guardrails, input) do
    Enum.reduce_while(guardrails, :ok, fn guardrail, :ok ->
      case invoke_guardrail(guardrail, input) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, guardrail_label(guardrail), reason}}

        {:interrupt, interrupt} ->
          {:halt, {:interrupt, guardrail_label(guardrail), normalize_interrupt(interrupt)}}

        other ->
          {:halt, {:error, guardrail_label(guardrail), invalid_result_message(other)}}
      end
    end)
  end

  defp invalid_result_message(other) do
    "guardrails must return :ok, {:error, reason}, or {:interrupt, interrupt}; got: #{inspect(other)}"
  end

  defp guardrail_label(module) when is_atom(module) do
    case Moto.Guardrail.guardrail_name(module) do
      {:ok, name} -> name
      {:error, _reason} -> inspect(module)
    end
  end

  defp guardrail_label({module, function, args}),
    do: "#{inspect(module)}.#{function}/#{length(args) + 1}"

  defp guardrail_label(fun) when is_function(fun, 1), do: "anonymous_guardrail"

  defp invoke_guardrail(module, input) when is_atom(module) do
    invoke_with_timeout(fn -> module.call(input) end)
  end

  defp invoke_guardrail({module, function, args}, input) do
    invoke_with_timeout(fn -> apply(module, function, [input | args]) end)
  end

  defp invoke_guardrail(fun, input) when is_function(fun, 1) do
    invoke_with_timeout(fn -> fun.(input) end)
  end

  defp invoke_with_timeout(fun) do
    task = Task.async(fun)

    case Task.yield(task, @guardrail_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp put_request_guardrail_meta(agent, request_id, guardrail_meta) do
    update_in(agent.state, [:requests, request_id], fn
      nil ->
        %{meta: %{moto_guardrails: guardrail_meta}}

      request ->
        meta =
          request
          |> Map.get(:meta, %{})
          |> Map.put(:moto_guardrails, guardrail_meta)

        Map.put(request, :meta, meta)
    end)
    |> then(&%{agent | state: &1})
  end

  defp get_request_guardrail_meta(agent, request_id) do
    get_in(agent.state, [:requests, request_id, :meta, :moto_guardrails])
  end

  defp run_output_guardrails(agent, request_id, directives) when is_binary(request_id) do
    case {get_request_guardrail_meta(agent, request_id), current_outcome(agent, request_id)} do
      {%{} = meta, outcome} when not is_nil(outcome) ->
        if Map.get(meta, :output_applied?, false) do
          {:ok, agent, directives}
        else
          input = %Output{
            agent: agent,
            server: self(),
            request_id: request_id,
            message: meta[:message] || "",
            context: meta[:context] || %{},
            allowed_tools: meta[:allowed_tools],
            llm_opts: meta[:llm_opts] || [],
            metadata: meta[:metadata] || %{},
            request_opts: meta[:request_opts] || %{},
            outcome: outcome
          }

          case run_output(get_in(meta, [:guardrails, :output]) || [], input) do
            :ok ->
              {:ok,
               put_request_guardrail_meta(
                 agent,
                 request_id,
                 Map.put(meta, :output_applied?, true)
               ), directives}

            {:error, label, reason} ->
              error = normalize_guardrail_error(:output, label, reason, agent, request_id)

              agent =
                agent
                |> force_request_failure(request_id, error)
                |> put_request_guardrail_meta(
                  request_id,
                  meta
                  |> Map.put(:output_applied?, true)
                  |> Map.put(:error, error)
                )

              {:ok, agent, directives}

            {:interrupt, label, %Interrupt{} = interrupt} ->
              agent =
                agent
                |> force_request_failure(request_id, {:interrupt, interrupt})
                |> put_request_guardrail_meta(
                  request_id,
                  meta
                  |> Map.put(:output_applied?, true)
                  |> Map.put(:interrupt, interrupt)
                  |> Map.put(:interrupt_guardrail, label)
                )

              Moto.Hooks.notify_interrupt(agent, request_id, interrupt)
              {:ok, agent, directives}
          end
        end

      _ ->
        {:ok, agent, directives}
    end
  end

  defp run_output_guardrails(agent, _request_id, directives), do: {:ok, agent, directives}

  defp force_request_failure(agent, request_id, error) do
    state =
      update_in(agent.state, [:requests, request_id], fn
        nil ->
          %{status: :failed, error: error, completed_at: System.system_time(:millisecond)}

        req ->
          req
          |> Map.put(:status, :failed)
          |> Map.put(:error, error)
          |> Map.put(:completed_at, System.system_time(:millisecond))
          |> Map.delete(:result)
      end)

    %{agent | state: Map.put(state, :completed, true)}
  end

  defp current_outcome(agent, request_id) do
    case Request.get_result(agent, request_id) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
      _ -> nil
    end
  end

  defp normalize_interrupt(%Interrupt{} = interrupt), do: interrupt
  defp normalize_interrupt(interrupt), do: Interrupt.new(interrupt)

  defp normalize_guardrail_error(stage, label, reason, agent, request_id) do
    Moto.Error.Normalize.guardrail_error(stage, label, reason,
      agent_id: Map.get(agent, :id),
      request_id: request_id
    )
  end
end
