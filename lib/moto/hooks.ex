defmodule Moto.Hooks do
  @moduledoc false

  require Logger

  alias Jido.AI.Request
  alias Moto.Interrupt

  @request_hooks_key :__moto_hooks__
  @stages [:before_turn, :after_turn, :on_interrupt]
  @hook_timeout_ms 5_000

  defmodule BeforeTurn do
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

  defmodule AfterTurn do
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

  defmodule InterruptInput do
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
      :interrupt
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
      :interrupt
    ]
  end

  @type stage :: :before_turn | :after_turn | :on_interrupt
  @type hook_ref :: module() | {module(), atom(), [term()]} | (term() -> term())
  @type stage_map :: %{
          before_turn: [hook_ref()],
          after_turn: [hook_ref()],
          on_interrupt: [hook_ref()]
        }

  @spec default_stage_map() :: stage_map()
  def default_stage_map do
    %{before_turn: [], after_turn: [], on_interrupt: []}
  end

  @spec translate_chat_result({:ok, term()} | {:error, term()} | {:interrupt, Interrupt.t()}) ::
          {:ok, term()} | {:error, term()} | {:interrupt, Interrupt.t()}
  def translate_chat_result({:error, {:interrupt, %Interrupt{} = interrupt}}),
    do: {:interrupt, interrupt}

  def translate_chat_result({:error, {:failed, _status, {:interrupt, %Interrupt{} = interrupt}}}),
    do: {:interrupt, interrupt}

  def translate_chat_result({:error, {:failed, _status, reason}}),
    do: {:error, reason}

  def translate_chat_result({:ok, {:interrupt, %Interrupt{} = interrupt}}),
    do: {:interrupt, interrupt}

  def translate_chat_result(other), do: other

  @spec notify_interrupt(Jido.Agent.t(), String.t(), Interrupt.t()) :: :ok
  def notify_interrupt(agent, request_id, %Interrupt{} = interrupt) when is_binary(request_id) do
    hook_meta = get_request_hook_meta(agent, request_id) || %{}

    invoke_interrupt_hooks(
      get_in(hook_meta, [:hooks, :on_interrupt]) || [],
      interrupt_input(agent, request_id, hook_meta, interrupt)
    )
  end

  def notify_interrupt(_agent, _request_id, _interrupt), do: :ok

  @spec normalize_dsl_hooks(stage_map()) :: {:ok, stage_map()} | {:error, String.t()}
  def normalize_dsl_hooks(hooks) when is_map(hooks) do
    Enum.reduce_while(@stages, {:ok, default_stage_map()}, fn stage, {:ok, acc} ->
      case normalize_stage_list(Map.get(hooks, stage, []), stage, :dsl) do
        {:ok, normalized} -> {:cont, {:ok, Map.put(acc, stage, normalized)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec normalize_request_hooks(term()) :: {:ok, stage_map()} | {:error, term()}
  def normalize_request_hooks(nil), do: {:ok, default_stage_map()}

  def normalize_request_hooks(hooks) when is_list(hooks) or is_map(hooks) do
    hooks
    |> Map.new()
    |> normalize_stage_map(:runtime)
  end

  def normalize_request_hooks(other),
    do:
      {:error,
       {:invalid_hook_spec, "hooks must be a keyword list or map, got: #{inspect(other)}"}}

  @spec validate_dsl_hook_ref(stage(), term()) :: :ok | {:error, String.t()}
  def validate_dsl_hook_ref(stage, ref) when stage in @stages do
    case normalize_stage_ref(ref, stage, :dsl) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec attach_request_hooks(map(), stage_map()) :: map()
  def attach_request_hooks(context, hooks) when is_map(context) and is_map(hooks) do
    maybe_attach_request_hooks(context, hooks)
  end

  @spec on_before_cmd(module(), Jido.Agent.t(), term(), stage_map(), map()) ::
          {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(
        _agent_module,
        agent,
        {:ai_react_start, %{query: query} = params},
        defaults,
        default_context
      ) do
    request_id = params[:request_id] || agent.state[:last_request_id]
    params = merge_default_context(params, default_context)

    {request_hooks, params} = pop_request_hooks(params)
    hooks = combine(defaults, request_hooks)

    input = %BeforeTurn{
      agent: agent,
      server: self(),
      request_id: request_id,
      message: query,
      context: Map.get(params, :tool_context, %{}) || %{},
      allowed_tools: Map.get(params, :allowed_tools),
      llm_opts: Map.get(params, :llm_opts, []),
      metadata: %{},
      request_opts: params
    }

    with {:ok, input} <- run_before_turn(hooks.before_turn, input) do
      agent =
        put_request_hook_meta(agent, request_id, %{
          hooks: hooks,
          metadata: input.metadata,
          request_opts: input.request_opts,
          message: input.message,
          context: input.context,
          allowed_tools: input.allowed_tools,
          llm_opts: input.llm_opts
        })

      {:ok, agent, {:ai_react_start, apply_before_turn_input(params, input)}}
    else
      {:interrupt, %Interrupt{} = interrupt} ->
        hook_meta = %{
          hooks: hooks,
          metadata: input.metadata,
          request_opts: input.request_opts,
          message: input.message,
          context: input.context,
          allowed_tools: input.allowed_tools,
          llm_opts: input.llm_opts,
          interrupt: interrupt
        }

        agent =
          agent
          |> Request.fail_request(request_id, {:interrupt, interrupt})
          |> put_request_hook_meta(request_id, hook_meta)

        invoke_interrupt_hooks(
          hooks.on_interrupt,
          interrupt_input(agent, request_id, hook_meta, interrupt)
        )

        {:ok, agent,
         {:ai_react_request_error,
          %{request_id: request_id, reason: :interrupt, message: query}}}

      {:error, reason} ->
        agent =
          agent
          |> Request.fail_request(request_id, {:hook, :before_turn, reason})
          |> put_request_hook_meta(request_id, %{
            hooks: hooks,
            metadata: input.metadata,
            request_opts: input.request_opts,
            message: input.message,
            context: input.context,
            allowed_tools: input.allowed_tools,
            llm_opts: input.llm_opts
          })

        {:ok, agent,
         {:ai_react_request_error,
          %{request_id: request_id, reason: :hook_failed, message: query}}}
    end
  end

  def on_before_cmd(_agent_module, agent, action, _defaults, _default_context),
    do: {:ok, agent, action}

  @spec on_after_cmd(module(), Jido.Agent.t(), term(), [term()], stage_map()) ::
          {:ok, Jido.Agent.t(), [term()]}
  def on_after_cmd(
        _agent_module,
        agent,
        {:ai_react_start, %{request_id: request_id}},
        directives,
        _defaults
      ) do
    run_after_turn_hooks(agent, request_id, directives)
  end

  def on_after_cmd(_agent_module, agent, _action, directives, _defaults) do
    run_after_turn_hooks(agent, agent.state[:last_request_id], directives)
  end

  @spec combine(stage_map(), stage_map()) :: stage_map()
  def combine(defaults, request_hooks) do
    %{
      before_turn:
        Map.get(defaults, :before_turn, []) ++ Map.get(request_hooks, :before_turn, []),
      after_turn: Map.get(defaults, :after_turn, []) ++ Map.get(request_hooks, :after_turn, []),
      on_interrupt:
        Map.get(defaults, :on_interrupt, []) ++ Map.get(request_hooks, :on_interrupt, [])
    }
  end

  defp normalize_stage_map(hooks, mode) do
    Enum.reduce_while(Map.to_list(hooks), {:ok, default_stage_map()}, fn {key, value},
                                                                         {:ok, acc} ->
      with {:ok, stage} <- normalize_stage_key(key),
           {:ok, normalized} <- normalize_stage_list(value, stage, mode) do
        {:cont, {:ok, Map.put(acc, stage, normalized)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_stage_key(stage) when stage in @stages, do: {:ok, stage}

  defp normalize_stage_key(stage) when is_binary(stage) do
    try do
      case String.to_existing_atom(stage) do
        stage_atom when stage_atom in @stages -> {:ok, stage_atom}
        other -> {:error, {:invalid_hook_stage, other}}
      end
    rescue
      ArgumentError -> {:error, {:invalid_hook_stage, stage}}
    end
  end

  defp normalize_stage_key(stage), do: {:error, {:invalid_hook_stage, stage}}

  defp normalize_stage_list(value, stage, mode) do
    refs =
      cond do
        value == [] -> []
        is_list(value) and not Keyword.keyword?(value) -> value
        value == nil -> []
        true -> [value]
      end

    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case normalize_stage_ref(ref, stage, mode) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, wrap_invalid_ref(stage, reason)}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_stage_ref(module, _stage, _mode) when is_atom(module) do
    case Moto.Hook.validate_hook_module(module) do
      :ok -> {:ok, module}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_stage_ref({module, function, args} = ref, _stage, _mode)
       when is_atom(module) and is_atom(function) and is_list(args) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        arity = length(args) + 1

        if function_exported?(module, function, arity) do
          {:ok, ref}
        else
          {:error,
           "hook MFA #{inspect(ref)} must export #{function}/#{arity} on #{inspect(module)}"}
        end

      {:error, reason} ->
        {:error, "hook module #{inspect(module)} could not be loaded: #{inspect(reason)}"}
    end
  end

  defp normalize_stage_ref(fun, _stage, :runtime) when is_function(fun, 1), do: {:ok, fun}

  defp normalize_stage_ref(fun, _stage, :dsl) when is_function(fun) do
    {:error,
     "DSL hooks do not support anonymous functions; use a Moto.Hook module or MFA instead"}
  end

  defp normalize_stage_ref(other, _stage, _mode),
    do:
      {:error,
       "hook refs must be a Moto.Hook module, MFA tuple, or runtime function, got: #{inspect(other)}"}

  defp wrap_invalid_ref(stage, reason) when is_binary(reason), do: {:invalid_hook, stage, reason}
  defp wrap_invalid_ref(stage, reason), do: {:invalid_hook, stage, inspect(reason)}

  defp maybe_attach_request_hooks(context, hooks) do
    if hooks == default_stage_map() do
      context
    else
      Map.put(context, @request_hooks_key, hooks)
    end
  end

  defp merge_default_context(params, default_context) when is_map(default_context) do
    merged_context =
      default_context
      |> Moto.Context.merge(Map.get(params, :tool_context, %{}) || %{})

    Map.put(params, :tool_context, merged_context)
  end

  defp pop_request_hooks(params) when is_map(params) do
    context = Map.get(params, :tool_context, %{}) || %{}
    {request_hooks, context} = Map.pop(context, @request_hooks_key, default_stage_map())
    {request_hooks, Map.put(params, :tool_context, context)}
  end

  defp run_before_turn(hooks, %BeforeTurn{} = input) do
    Enum.reduce_while(hooks, {:ok, input}, fn hook, {:ok, input_acc} ->
      case invoke_hook(hook, input_acc) do
        {:ok, overrides} ->
          with {:ok, input_acc} <- apply_before_turn_overrides(input_acc, overrides) do
            {:cont, {:ok, input_acc}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:interrupt, interrupt} ->
          {:halt, {:interrupt, normalize_interrupt(interrupt)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp run_after_turn(hooks, %AfterTurn{} = input) do
    hooks
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, input}, fn hook, {:ok, input_acc} ->
      case invoke_hook(hook, input_acc) do
        {:ok, {:ok, _} = outcome} ->
          {:cont, {:ok, %{input_acc | outcome: outcome}}}

        {:ok, {:error, _} = outcome} ->
          {:cont, {:ok, %{input_acc | outcome: outcome}}}

        {:interrupt, interrupt} ->
          {:halt, {:interrupt, normalize_interrupt(interrupt)}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        other ->
          {:halt,
           {:error,
            "after_turn hook must return {:ok, {:ok, result}}, {:ok, {:error, reason}}, {:interrupt, interrupt}, or {:error, reason}; got: #{inspect(other)}"}}
      end
    end)
  end

  defp invoke_interrupt_hooks(hooks, %InterruptInput{} = input) do
    hooks
    |> Enum.reverse()
    |> Enum.each(fn hook ->
      case invoke_hook(hook, input) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Moto on_interrupt hook failed: #{inspect(reason)}")

        other ->
          Logger.warning("Moto on_interrupt hook returned invalid result: #{inspect(other)}")
      end
    end)
  end

  defp apply_before_turn_input(params, %BeforeTurn{} = input) do
    params
    |> Map.put(:query, input.message)
    |> maybe_put_prompt(input.message)
    |> Map.put(:tool_context, input.context)
    |> Map.put(:runtime_context, input.context)
    |> maybe_put_optional(:allowed_tools, input.allowed_tools)
    |> maybe_put_optional(:llm_opts, input.llm_opts)
  end

  defp maybe_put_prompt(params, message) do
    if Map.has_key?(params, :prompt) do
      Map.put(params, :prompt, message)
    else
      params
    end
  end

  defp maybe_put_optional(params, _key, nil), do: params
  defp maybe_put_optional(params, key, value), do: Map.put(params, key, value)

  defp apply_before_turn_overrides(%BeforeTurn{} = input, overrides)
       when is_map(overrides) or is_list(overrides) do
    overrides = Map.new(overrides)
    allowed_keys = [:message, :context, :allowed_tools, :llm_opts, :metadata]

    case Map.keys(overrides) -- allowed_keys do
      [] ->
        with {:ok, context} <-
               normalize_override_context(Map.get(overrides, :context)),
             {:ok, allowed_tools} <-
               normalize_override_allowed_tools(Map.get(overrides, :allowed_tools)),
             {:ok, llm_opts} <- normalize_override_llm_opts(Map.get(overrides, :llm_opts)),
             {:ok, metadata} <- normalize_override_metadata(Map.get(overrides, :metadata)),
             {:ok, message} <-
               normalize_override_message(Map.get(overrides, :message, input.message)) do
          {:ok,
           %BeforeTurn{
             input
             | message: message,
               context: merge_optional(input.context, context),
               allowed_tools: coalesce_optional(allowed_tools, input.allowed_tools),
               llm_opts: coalesce_optional(llm_opts, input.llm_opts),
               metadata: Map.merge(input.metadata, metadata)
           }}
        end

      invalid_keys ->
        {:error,
         "before_turn hook returned unsupported override keys: #{Enum.join(Enum.map(invalid_keys, &inspect/1), ", ")}"}
    end
  end

  defp apply_before_turn_overrides(_input, other),
    do:
      {:error,
       "before_turn hook must return {:ok, map_or_keyword_overrides}, got: #{inspect(other)}"}

  defp normalize_override_message(message) when is_binary(message), do: {:ok, message}
  defp normalize_override_message(nil), do: {:ok, nil}

  defp normalize_override_message(other),
    do: {:error, "before_turn message override must be a string, got: #{inspect(other)}"}

  defp normalize_override_context(nil), do: {:ok, %{}}
  defp normalize_override_context(value) when is_map(value), do: {:ok, value}
  defp normalize_override_context(value) when is_list(value), do: {:ok, Map.new(value)}

  defp normalize_override_context(other),
    do:
      {:error,
       "before_turn context override must be a map or keyword list, got: #{inspect(other)}"}

  defp normalize_override_allowed_tools(nil), do: {:ok, nil}
  defp normalize_override_allowed_tools(value) when is_list(value), do: {:ok, value}

  defp normalize_override_allowed_tools(other),
    do: {:error, "before_turn allowed_tools override must be a list, got: #{inspect(other)}"}

  defp normalize_override_llm_opts(nil), do: {:ok, nil}
  defp normalize_override_llm_opts(value) when is_list(value), do: {:ok, value}
  defp normalize_override_llm_opts(value) when is_map(value), do: {:ok, value}

  defp normalize_override_llm_opts(other),
    do:
      {:error,
       "before_turn llm_opts override must be a map or keyword list, got: #{inspect(other)}"}

  defp normalize_override_metadata(nil), do: {:ok, %{}}
  defp normalize_override_metadata(value) when is_map(value), do: {:ok, value}
  defp normalize_override_metadata(value) when is_list(value), do: {:ok, Map.new(value)}

  defp normalize_override_metadata(other),
    do:
      {:error,
       "before_turn metadata override must be a map or keyword list, got: #{inspect(other)}"}

  defp merge_optional(left, right) when is_map(right) and map_size(right) > 0,
    do: Map.merge(left || %{}, right)

  defp merge_optional(left, _right), do: left

  defp coalesce_optional(nil, fallback), do: fallback
  defp coalesce_optional(value, _fallback), do: value

  defp current_outcome(agent, request_id) do
    case Request.get_result(agent, request_id) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
      _ -> nil
    end
  end

  defp persist_outcome(agent, request_id, {:ok, result}, hook_meta) do
    agent
    |> Request.complete_request(request_id, result)
    |> put_request_hook_meta(request_id, hook_meta)
  end

  defp persist_outcome(agent, request_id, {:error, reason}, hook_meta) do
    agent
    |> Request.fail_request(request_id, reason)
    |> put_request_hook_meta(request_id, hook_meta)
  end

  defp interrupt_input(agent, request_id, hook_meta, interrupt) do
    %InterruptInput{
      agent: agent,
      server: self(),
      request_id: request_id,
      message: hook_meta[:message] || "",
      context: hook_meta[:context] || %{},
      allowed_tools: hook_meta[:allowed_tools],
      llm_opts: hook_meta[:llm_opts] || [],
      metadata: hook_meta[:metadata] || %{},
      request_opts: hook_meta[:request_opts] || %{},
      interrupt: interrupt
    }
  end

  defp normalize_interrupt(%Interrupt{} = interrupt), do: interrupt

  defp normalize_interrupt(interrupt) when is_map(interrupt) or is_list(interrupt),
    do: Interrupt.new(interrupt)

  defp normalize_interrupt(other),
    do: Interrupt.new(%{kind: :interrupt, message: inspect(other), data: %{raw_interrupt: other}})

  defp invoke_hook(module, input) when is_atom(module) do
    invoke_with_timeout(fn -> module.call(input) end)
  end

  defp invoke_hook({module, function, args}, input) do
    invoke_with_timeout(fn -> apply(module, function, [input | args]) end)
  end

  defp invoke_hook(fun, input) when is_function(fun, 1) do
    invoke_with_timeout(fn -> fun.(input) end)
  end

  defp invoke_with_timeout(fun) do
    task = Task.async(fun)

    case Task.yield(task, @hook_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp put_request_hook_meta(agent, request_id, hook_meta) do
    update_in(agent.state, [:requests, request_id], fn
      nil ->
        %{meta: %{moto_hooks: hook_meta}}

      request ->
        meta =
          request
          |> Map.get(:meta, %{})
          |> Map.put(:moto_hooks, hook_meta)

        Map.put(request, :meta, meta)
    end)
    |> then(&%{agent | state: &1})
  end

  defp get_request_hook_meta(agent, request_id) do
    get_in(agent.state, [:requests, request_id, :meta, :moto_hooks])
  end

  defp run_after_turn_hooks(agent, request_id, directives) when is_binary(request_id) do
    hook_meta = get_request_hook_meta(agent, request_id)

    case {hook_meta, current_outcome(agent, request_id)} do
      {%{} = hook_meta, outcome} when not is_nil(outcome) ->
        if Map.get(hook_meta, :after_turn_applied?, false) do
          {:ok, agent, directives}
        else
          input = %AfterTurn{
            agent: agent,
            server: self(),
            request_id: request_id,
            message: hook_meta[:message] || "",
            context: hook_meta[:context] || %{},
            allowed_tools: hook_meta[:allowed_tools],
            llm_opts: hook_meta[:llm_opts] || [],
            metadata: hook_meta[:metadata] || %{},
            request_opts: hook_meta[:request_opts] || %{},
            outcome: outcome
          }

          case run_after_turn(get_in(hook_meta, [:hooks, :after_turn]) || [], input) do
            {:ok, input} ->
              updated_hook_meta =
                hook_meta
                |> Map.put(:metadata, input.metadata)
                |> Map.put(:after_turn_applied?, true)

              agent =
                persist_outcome(agent, request_id, input.outcome, updated_hook_meta)

              {:ok, agent, directives}

            {:interrupt, %Interrupt{} = interrupt} ->
              hook_meta = Map.put(hook_meta, :after_turn_applied?, true)

              agent =
                agent
                |> Request.fail_request(request_id, {:interrupt, interrupt})
                |> put_request_hook_meta(request_id, Map.put(hook_meta, :interrupt, interrupt))

              invoke_interrupt_hooks(
                get_in(hook_meta, [:hooks, :on_interrupt]) || [],
                interrupt_input(agent, request_id, hook_meta, interrupt)
              )

              {:ok, agent, directives}

            {:error, reason} ->
              agent =
                agent
                |> Request.fail_request(request_id, {:hook, :after_turn, reason})
                |> put_request_hook_meta(
                  request_id,
                  Map.put(hook_meta, :after_turn_applied?, true)
                )

              {:ok, agent, directives}
          end
        end

      _ ->
        {:ok, agent, directives}
    end
  end

  defp run_after_turn_hooks(agent, _request_id, directives), do: {:ok, agent, directives}
end
