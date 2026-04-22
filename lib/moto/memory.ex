defmodule Moto.Memory do
  @moduledoc false

  require Logger

  alias Jido.AI.Request

  @memory_context_key :__moto_memory__
  @default_retrieve_limit 5
  @default_config %{
    mode: :conversation,
    namespace: :per_agent,
    capture: :conversation,
    retrieve: %{limit: @default_retrieve_limit},
    inject: :system_prompt
  }

  @type namespace_mode :: :per_agent | {:shared, String.t()} | {:context, atom() | String.t()}
  @type capture_mode :: :conversation | :off
  @type inject_mode :: :system_prompt | :context
  @type config :: %{
          mode: :conversation,
          namespace: namespace_mode(),
          capture: capture_mode(),
          retrieve: %{limit: pos_integer()},
          inject: inject_mode()
        }

  @spec context_key() :: atom()
  def context_key, do: @memory_context_key

  @spec default_config() :: config()
  def default_config, do: @default_config

  @spec enabled?(config() | nil) :: boolean()
  def enabled?(nil), do: false
  def enabled?(%{}), do: true

  @spec requires_request_transformer?(config() | nil) :: boolean()
  def requires_request_transformer?(%{inject: :system_prompt}), do: true
  def requires_request_transformer?(_), do: false

  @spec prompt_text(map()) :: String.t() | nil
  def prompt_text(runtime_context) when is_map(runtime_context) do
    runtime_context
    |> Map.get(@memory_context_key, %{})
    |> Map.get(:prompt)
    |> case do
      prompt when is_binary(prompt) and prompt != "" -> prompt
      _ -> nil
    end
  end

  @spec normalize_dsl([struct()]) :: {:ok, config() | nil} | {:error, String.t()}
  def normalize_dsl([]), do: {:ok, nil}

  def normalize_dsl(entries) when is_list(entries) do
    with {:ok, attrs} <- reduce_dsl_entries(entries),
         {:ok, normalized} <- normalize_map(attrs) do
      {:ok, normalized}
    end
  end

  @spec normalize_imported(nil | map()) :: {:ok, config() | nil} | {:error, String.t()}
  def normalize_imported(nil), do: {:ok, nil}

  def normalize_imported(%{} = memory) do
    attrs =
      memory
      |> normalize_imported_namespace()
      |> Map.put(:mode, imported_atom(get_value(memory, :mode)))
      |> Map.put(:capture, imported_atom(get_value(memory, :capture)))
      |> Map.put(:inject, imported_atom(get_value(memory, :inject)))
      |> Map.put(
        :retrieve,
        memory
        |> get_value(:retrieve, %{})
        |> normalize_imported_retrieve()
      )

    normalize_map(attrs)
  end

  def normalize_imported(other),
    do: {:error, "memory must be a map, got: #{inspect(other)}"}

  @spec validate_dsl_entry(struct()) :: :ok | {:error, String.t()}
  def validate_dsl_entry(%Moto.Agent.Dsl.MemoryMode{value: value}),
    do: validate_mode(value)

  def validate_dsl_entry(%Moto.Agent.Dsl.MemoryNamespace{value: value}),
    do: validate_namespace_entry(value)

  def validate_dsl_entry(%Moto.Agent.Dsl.MemorySharedNamespace{value: value}),
    do: validate_shared_namespace(value)

  def validate_dsl_entry(%Moto.Agent.Dsl.MemoryCapture{value: value}),
    do: validate_capture(value)

  def validate_dsl_entry(%Moto.Agent.Dsl.MemoryInject{value: value}),
    do: validate_inject(value)

  def validate_dsl_entry(%Moto.Agent.Dsl.MemoryRetrieve{limit: limit}),
    do: validate_limit(limit)

  @spec runtime_plugin(config() | nil) :: nil | {module(), map()}
  def runtime_plugin(nil), do: nil

  def runtime_plugin(%{} = config) do
    {Moto.Plugins.Memory, plugin_config(config)}
  end

  @spec on_before_cmd(Jido.Agent.t(), term(), config() | nil, map()) ::
          {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(agent, action, nil, _default_context), do: {:ok, agent, action}

  def on_before_cmd(
        agent,
        {:ai_react_start, %{query: query} = params},
        %{} = config,
        default_context
      ) do
    request_id = params[:request_id] || agent.state[:last_request_id]
    params = merge_default_context(params, default_context)
    context = Map.get(params, :tool_context, %{}) || %{}

    with {:ok, namespace} <- resolve_namespace(agent, context, config),
         {:ok, records} <- retrieve_records(agent, namespace, config),
         context <- attach_memory(context, namespace, records, config),
         params <- params |> Map.put(:tool_context, context) |> Map.put(:runtime_context, context),
         agent <-
           put_request_memory_meta(
             agent,
             request_id,
             build_request_meta(config, namespace, records, query, context)
           ) do
      {:ok, agent, {:ai_react_start, params}}
    else
      {:error, reason} when is_binary(request_id) ->
        Logger.warning("Moto memory retrieval failed: #{inspect(reason)}")

        failed_agent =
          agent
          |> Request.fail_request(request_id, {:memory, reason})
          |> put_request_memory_meta(request_id, %{error: reason})

        {:ok, failed_agent,
         {:ai_react_request_error, %{request_id: request_id, reason: :memory_failed, message: query}}}

      {:error, reason} ->
        Logger.warning("Moto memory retrieval failed: #{inspect(reason)}")

        {:ok, agent, {:ai_react_request_error, %{request_id: request_id, reason: :memory_failed, message: query}}}
    end
  end

  def on_before_cmd(agent, action, _config, _default_context), do: {:ok, agent, action}

  @spec on_after_cmd(Jido.Agent.t(), term(), [term()], config() | nil) ::
          {:ok, Jido.Agent.t(), [term()]}
  def on_after_cmd(agent, _action, directives, nil), do: {:ok, agent, directives}

  def on_after_cmd(agent, {:ai_react_start, %{request_id: request_id}}, directives, %{} = config)
      when is_binary(request_id) do
    case get_request_memory_meta(agent, request_id) do
      %{captured?: true} ->
        {:ok, agent, directives}

      %{error: _reason} ->
        {:ok, agent, directives}

      %{} = meta ->
        capture_conversation(agent, request_id, directives, config, meta)

      _ ->
        {:ok, agent, directives}
    end
  end

  def on_after_cmd(agent, _action, directives, _config), do: {:ok, agent, directives}

  defp capture_conversation(agent, request_id, directives, %{capture: :off}, meta) do
    {:ok, put_request_memory_meta(agent, request_id, Map.put(meta, :captured?, false)), directives}
  end

  defp capture_conversation(
         agent,
         request_id,
         directives,
         %{capture: :conversation} = _config,
         meta
       ) do
    case Request.get_result(agent, request_id) do
      {:ok, result} ->
        with :ok <- remember_turn(agent, meta.namespace, user_record(meta, request_id)),
             :ok <-
               remember_turn(
                 agent,
                 meta.namespace,
                 assistant_record(agent, meta, request_id, result)
               ) do
          {:ok, put_request_memory_meta(agent, request_id, Map.put(meta, :captured?, true)), directives}
        else
          {:error, reason} ->
            Logger.warning("Moto memory capture failed: #{inspect(reason)}")

            {:ok,
             put_request_memory_meta(
               agent,
               request_id,
               meta
               |> Map.put(:captured?, false)
               |> Map.put(:capture_error, reason)
             ), directives}
        end

      _ ->
        {:ok, agent, directives}
    end
  end

  defp reduce_dsl_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
      with :ok <- ensure_unique_entry(entry, acc) do
        {:cont, {:ok, put_entry(entry, acc)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp put_entry(%Moto.Agent.Dsl.MemoryMode{value: value}, acc), do: Map.put(acc, :mode, value)

  defp put_entry(%Moto.Agent.Dsl.MemoryNamespace{value: value}, acc),
    do: Map.put(acc, :namespace, value)

  defp put_entry(%Moto.Agent.Dsl.MemorySharedNamespace{value: value}, acc),
    do: Map.put(acc, :shared_namespace, value)

  defp put_entry(%Moto.Agent.Dsl.MemoryCapture{value: value}, acc),
    do: Map.put(acc, :capture, value)

  defp put_entry(%Moto.Agent.Dsl.MemoryInject{value: value}, acc),
    do: Map.put(acc, :inject, value)

  defp put_entry(%Moto.Agent.Dsl.MemoryRetrieve{limit: limit}, acc),
    do: Map.put(acc, :retrieve, %{limit: limit})

  defp ensure_unique_entry(%module{} = entry, acc) do
    key = dsl_entry_key(module)

    if Map.has_key?(acc, key) do
      {:error, "duplicate memory #{key} entry in Moto agent"}
    else
      validate_dsl_entry(entry)
    end
  end

  defp dsl_entry_key(Moto.Agent.Dsl.MemoryMode), do: :mode
  defp dsl_entry_key(Moto.Agent.Dsl.MemoryNamespace), do: :namespace
  defp dsl_entry_key(Moto.Agent.Dsl.MemorySharedNamespace), do: :shared_namespace
  defp dsl_entry_key(Moto.Agent.Dsl.MemoryCapture), do: :capture
  defp dsl_entry_key(Moto.Agent.Dsl.MemoryInject), do: :inject
  defp dsl_entry_key(Moto.Agent.Dsl.MemoryRetrieve), do: :retrieve

  defp normalize_map(attrs) when is_map(attrs) do
    mode = Map.get(attrs, :mode, @default_config.mode)
    namespace = Map.get(attrs, :namespace, @default_config.namespace)
    shared_namespace = Map.get(attrs, :shared_namespace)
    capture = Map.get(attrs, :capture, @default_config.capture)
    inject = Map.get(attrs, :inject, @default_config.inject)
    retrieve = Map.get(attrs, :retrieve, @default_config.retrieve)

    with :ok <- validate_mode(mode),
         {:ok, namespace} <- validate_namespace(namespace, shared_namespace),
         :ok <- validate_capture(capture),
         :ok <- validate_inject(inject),
         {:ok, retrieve} <- normalize_retrieve(retrieve) do
      {:ok,
       %{
         mode: :conversation,
         namespace: namespace,
         capture: capture,
         retrieve: retrieve,
         inject: inject
       }}
    end
  end

  defp validate_mode(:conversation), do: :ok

  defp validate_mode(other),
    do: {:error, "memory mode must be :conversation, got: #{inspect(other)}"}

  defp validate_namespace_entry(:per_agent), do: :ok
  defp validate_namespace_entry(:shared), do: :ok
  defp validate_namespace_entry({:context, key}) when is_atom(key) or is_binary(key), do: :ok

  defp validate_namespace_entry(other) do
    {:error, "memory namespace must be :per_agent, :shared, or {:context, key}, got: #{inspect(other)}"}
  end

  defp validate_namespace(:per_agent, _shared_namespace), do: {:ok, :per_agent}

  defp validate_namespace(:shared, shared_namespace) do
    with :ok <- validate_shared_namespace_for_namespace(shared_namespace) do
      {:ok, {:shared, String.trim(shared_namespace)}}
    end
  end

  defp validate_namespace({:context, key}, _shared_namespace)
       when is_atom(key) or is_binary(key) do
    {:ok, {:context, key}}
  end

  defp validate_namespace(other, _shared_namespace) do
    {:error,
     "memory namespace must be :per_agent, :shared with shared_namespace, or {:context, key}, got: #{inspect(other)}"}
  end

  defp validate_shared_namespace(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, "memory shared_namespace must not be empty"}
    else
      :ok
    end
  end

  defp validate_shared_namespace(_),
    do: {:error, "memory shared_namespace must be a non-empty string"}

  defp validate_shared_namespace_for_namespace(value) do
    case validate_shared_namespace(value) do
      :ok ->
        :ok

      {:error, _reason} ->
        {:error, "memory namespace must be :per_agent, :shared with shared_namespace, or {:context, key}, got: :shared"}
    end
  end

  defp validate_capture(:conversation), do: :ok
  defp validate_capture(:off), do: :ok

  defp validate_capture(other),
    do: {:error, "memory capture must be :conversation or :off, got: #{inspect(other)}"}

  defp validate_inject(:system_prompt), do: :ok
  defp validate_inject(:context), do: :ok

  defp validate_inject(other),
    do: {:error, "memory inject must be :system_prompt or :context, got: #{inspect(other)}"}

  defp normalize_retrieve(%{limit: limit}),
    do: with(:ok <- validate_limit(limit), do: {:ok, %{limit: limit}})

  defp normalize_retrieve(limit) when is_integer(limit), do: normalize_retrieve(%{limit: limit})
  defp normalize_retrieve(_), do: {:ok, %{limit: @default_retrieve_limit}}

  defp validate_limit(limit) when is_integer(limit) and limit > 0, do: :ok

  defp validate_limit(other),
    do: {:error, "memory retrieve limit must be a positive integer, got: #{inspect(other)}"}

  defp normalize_imported_namespace(memory) do
    case get_value(memory, :namespace, "per_agent") do
      "per_agent" ->
        %{namespace: :per_agent}

      :per_agent ->
        %{namespace: :per_agent}

      "shared" ->
        %{namespace: :shared, shared_namespace: get_value(memory, :shared_namespace)}

      :shared ->
        %{namespace: :shared, shared_namespace: get_value(memory, :shared_namespace)}

      "context" ->
        %{namespace: {:context, get_value(memory, :context_namespace_key)}}

      :context ->
        %{namespace: {:context, get_value(memory, :context_namespace_key)}}

      other ->
        %{namespace: other}
    end
  end

  defp normalize_imported_retrieve(%{} = retrieve) do
    %{limit: get_value(retrieve, :limit, @default_retrieve_limit)}
  end

  defp normalize_imported_retrieve(_), do: %{limit: @default_retrieve_limit}

  defp plugin_config(%{namespace: :per_agent}) do
    %{
      store: {Jido.Memory.Store.ETS, [table: :moto_memory]},
      store_opts: [],
      namespace_mode: :per_agent,
      auto_capture: false
    }
  end

  defp plugin_config(%{namespace: {:shared, shared_namespace}}) do
    %{
      store: {Jido.Memory.Store.ETS, [table: :moto_memory]},
      store_opts: [],
      namespace_mode: :shared,
      shared_namespace: shared_namespace,
      auto_capture: false
    }
  end

  defp plugin_config(%{namespace: {:context, _key}}) do
    %{
      store: {Jido.Memory.Store.ETS, [table: :moto_memory]},
      store_opts: [],
      namespace_mode: :per_agent,
      auto_capture: false
    }
  end

  defp merge_default_context(params, default_context)
       when is_map(params) and is_map(default_context) do
    context =
      default_context
      |> Moto.Context.merge(Map.get(params, :tool_context, %{}) || %{})

    params
    |> Map.put(:tool_context, context)
    |> Map.put(:runtime_context, context)
  end

  defp resolve_namespace(agent, _context, %{namespace: :per_agent}) do
    with %{} = plugin_state <- Map.get(agent.state, plugin_state_key(), %{}),
         namespace when is_binary(namespace) <- Map.get(plugin_state, :namespace) do
      {:ok, namespace}
    else
      _ -> {:error, :namespace_required}
    end
  end

  defp resolve_namespace(agent, _context, %{namespace: {:shared, shared_namespace}}) do
    if is_binary(shared_namespace) and shared_namespace != "" do
      {:ok, "shared:" <> shared_namespace}
    else
      resolve_namespace(agent, %{}, %{namespace: :per_agent})
    end
  end

  defp resolve_namespace(agent, context, %{namespace: {:context, key}}) do
    case get_value(context, key) do
      nil ->
        {:error, {:missing_context_namespace, key}}

      value ->
        {:ok,
         "agent:" <>
           namespace_agent_key(agent) <>
           ":context:" <> namespace_key(key) <> ":" <> namespace_value(value)}
    end
  end

  defp retrieve_records(agent, namespace, %{retrieve: %{limit: limit}}) do
    case Jido.Memory.Runtime.retrieve(
           agent,
           %{
             namespace: namespace,
             classes: [:episodic],
             kinds: [:user_turn, :assistant_turn],
             limit: limit,
             order: :desc
           },
           memory_runtime_opts(agent, namespace)
         ) do
      {:ok, result} ->
        {:ok,
         result.hits
         |> Enum.map(& &1.record)
         |> Enum.sort_by(&record_sort_key/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp attach_memory(context, namespace, records, config) do
    memory_payload = %{
      namespace: namespace,
      records: records,
      prompt: prompt_for_records(records),
      inject: config.inject
    }

    context =
      context
      |> Map.put(@memory_context_key, memory_payload)
      |> maybe_put_public_memory(memory_payload, config)

    context
  end

  defp maybe_put_public_memory(context, payload, %{inject: :context}) do
    Map.put(context, :memory, %{namespace: payload.namespace, records: payload.records})
  end

  defp maybe_put_public_memory(context, _payload, _config), do: context

  defp build_request_meta(config, namespace, records, message, context) do
    %{
      config: config,
      namespace: namespace,
      records: records,
      message: message,
      context: context,
      captured?: false
    }
  end

  defp prompt_for_records([]), do: nil

  defp prompt_for_records(records) do
    lines =
      records
      |> Enum.map(&record_prompt_line/1)
      |> Enum.reject(&is_nil/1)

    if lines == [] do
      nil
    else
      Enum.join(["Relevant memory:" | lines], "\n")
    end
  end

  defp record_prompt_line(%{kind: kind} = record) do
    label =
      case kind do
        :user_turn -> "User"
        "user_turn" -> "User"
        :assistant_turn -> "Assistant"
        "assistant_turn" -> "Assistant"
        _ -> "Memory"
      end

    case record_text(record) do
      nil -> nil
      text -> "- #{label}: #{text}"
    end
  end

  defp remember_turn(agent, namespace, attrs) do
    case Jido.Memory.Runtime.remember(
           agent,
           Map.put(attrs, :namespace, namespace),
           memory_runtime_opts(agent, namespace)
         ) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp user_record(meta, request_id) do
    %{
      class: :episodic,
      kind: :user_turn,
      text: meta.message,
      content: %{role: "user", message: meta.message},
      tags: ["moto", "conversation", "user"],
      source: "/moto/agent",
      metadata: capture_metadata(meta.context, request_id)
    }
  end

  defp assistant_record(agent, meta, request_id, result) do
    text = record_text(result)

    %{
      class: :episodic,
      kind: :assistant_turn,
      text: text,
      content: %{role: "assistant", result: result},
      tags: ["moto", "conversation", "assistant"],
      source: "/moto/agent",
      metadata:
        capture_metadata(meta.context, request_id)
        |> Map.put(:agent, agent.name)
    }
  end

  defp capture_metadata(context, request_id) do
    %{
      turn_id: request_id
    }
    |> maybe_put_metadata(:actor, get_value(context, :actor))
    |> maybe_put_metadata(
      :session_id,
      get_value(context, :session_id, get_value(context, :session))
    )
    |> maybe_put_metadata(:tenant, get_value(context, :tenant))
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp namespace_agent_key(%{name: name}) when is_binary(name), do: name
  defp namespace_agent_key(%{id: id}) when is_binary(id), do: id
  defp namespace_agent_key(_agent), do: "agent"

  defp namespace_key(key) when is_atom(key), do: Atom.to_string(key)
  defp namespace_key(key) when is_binary(key), do: String.trim(key)

  defp namespace_value(value) when is_binary(value), do: String.trim(value)
  defp namespace_value(value) when is_atom(value), do: Atom.to_string(value)
  defp namespace_value(value) when is_integer(value), do: Integer.to_string(value)
  defp namespace_value(value), do: inspect(value)

  defp record_text(%{text: text}) when is_binary(text) and text != "", do: text
  defp record_text(%{content: content}) when is_binary(content) and content != "", do: content

  defp record_text(%{content: %{message: message}}) when is_binary(message) and message != "",
    do: message

  defp record_text(%{content: %{result: result}}), do: record_text(result)
  defp record_text(result) when is_binary(result) and result != "", do: result
  defp record_text(nil), do: nil
  defp record_text(other), do: inspect(other)

  defp record_sort_key(record) do
    {
      Map.get(record, :observed_at, 0),
      kind_sort_rank(Map.get(record, :kind)),
      Map.get(record, :id, "")
    }
  end

  defp kind_sort_rank(:user_turn), do: 0
  defp kind_sort_rank("user_turn"), do: 0
  defp kind_sort_rank(:assistant_turn), do: 1
  defp kind_sort_rank("assistant_turn"), do: 1
  defp kind_sort_rank(_other), do: 2

  defp plugin_state_key, do: Moto.Plugins.Memory.state_key()

  defp memory_runtime_opts(agent, namespace) do
    plugin_state = Map.get(agent.state, plugin_state_key(), %{})

    []
    |> Keyword.put(:namespace, namespace)
    |> maybe_put_runtime_store(Map.get(plugin_state, :store))
  end

  defp maybe_put_runtime_store(opts, {store_mod, store_opts})
       when is_atom(store_mod) and is_list(store_opts) do
    opts
    |> Keyword.put(:store, store_mod)
    |> Keyword.put(:store_opts, store_opts)
  end

  defp maybe_put_runtime_store(opts, _store), do: opts

  defp put_request_memory_meta(agent, request_id, memory_meta) when is_binary(request_id) do
    update_in(agent.state, [:requests, request_id], fn
      nil ->
        %{meta: %{moto_memory: memory_meta}}

      request ->
        meta =
          request
          |> Map.get(:meta, %{})
          |> Map.put(:moto_memory, memory_meta)

        Map.put(request, :meta, meta)
    end)
    |> then(&%{agent | state: &1})
  end

  defp put_request_memory_meta(agent, _request_id, _memory_meta), do: agent

  defp get_request_memory_meta(agent, request_id) when is_binary(request_id) do
    get_in(agent.state, [:requests, request_id, :meta, :moto_memory])
  end

  defp get_value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, normalize_lookup_key(key), default))
  end

  defp imported_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> String.to_atom(normalized)
    end
  end

  defp imported_atom(value), do: value

  defp normalize_lookup_key(key) when is_atom(key), do: Atom.to_string(key)

  defp normalize_lookup_key(key) when is_binary(key) do
    case safe_existing_atom(key) do
      nil -> key
      atom -> atom
    end
  end

  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
