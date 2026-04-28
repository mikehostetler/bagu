defmodule Jidoka.Output do
  @moduledoc """
  Structured final-output contracts for Jidoka agents.
  """

  alias Jido.AI.Request

  @context_key :__jidoka_output__
  @max_retries 3
  @default_retries 1
  @default_on_validation_error :repair
  @raw_preview_bytes 500

  @type schema_kind :: :zoi | :json_schema
  @type validation_mode :: :repair | :error

  @type t :: %__MODULE__{
          schema: Zoi.schema() | map(),
          schema_kind: schema_kind(),
          retries: non_neg_integer(),
          on_validation_error: validation_mode()
        }

  defstruct [
    :schema,
    schema_kind: :zoi,
    retries: @default_retries,
    on_validation_error: @default_on_validation_error
  ]

  @doc false
  @spec context_key() :: atom()
  def context_key, do: @context_key

  @doc """
  Builds a structured output contract from DSL/imported options.
  """
  @spec new(keyword() | map() | t() | nil) :: {:ok, t() | nil} | {:error, term()}
  def new(nil), do: {:ok, nil}
  def new(%__MODULE__{} = output), do: {:ok, output}

  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    schema =
      Map.get(attrs, :schema) ||
        Map.get(attrs, "schema") ||
        Map.get(attrs, :object_schema) ||
        Map.get(attrs, "object_schema")

    retries = Map.get(attrs, :retries, Map.get(attrs, "retries", @default_retries))
    mode = Map.get(attrs, :on_validation_error, Map.get(attrs, "on_validation_error", @default_on_validation_error))

    with {:ok, schema_kind} <- schema_kind(schema),
         {:ok, retries} <- normalize_retries(retries),
         {:ok, mode} <- normalize_mode(mode),
         :ok <- validate_schema_shape(schema, schema_kind) do
      {:ok, %__MODULE__{schema: schema, schema_kind: schema_kind, retries: retries, on_validation_error: mode}}
    end
  end

  def new(other), do: {:error, "output must be a map or keyword list, got: #{inspect(other)}"}

  @doc """
  Validates a parsed output value against the configured schema.
  """
  @spec validate(t(), term()) :: {:ok, map()} | {:error, term()}
  def validate(%__MODULE__{schema_kind: :zoi, schema: schema}, value) when is_map(value) do
    value = normalize_zoi_input(schema, value)

    case Zoi.parse(schema, value) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error, output_error(:expected_map_result, other, value)}

      {:error, errors} ->
        {:error, output_error({:schema, Zoi.treefy_errors(errors)}, value)}
    end
  end

  def validate(%__MODULE__{schema_kind: :json_schema, schema: schema}, value) when is_map(value) do
    case ReqLLM.Schema.validate(value, schema) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error, output_error(:expected_map_result, other, value)}

      {:error, reason} ->
        {:error, output_error({:schema, reason_message(reason)}, value)}
    end
  end

  def validate(%__MODULE__{}, value), do: {:error, output_error(:expected_map, value)}

  @doc """
  Parses and validates raw model output.
  """
  @spec parse(t(), term()) :: {:ok, map()} | {:error, term()}
  def parse(%__MODULE__{} = output, %ReqLLM.Response{} = response) do
    case ReqLLM.Response.unwrap_object(response, json_repair: true) do
      {:ok, object} -> validate(output, object)
      {:error, reason} -> {:error, output_error({:parse, reason_message(reason)}, response)}
    end
  end

  def parse(%__MODULE__{} = output, value) when is_map(value) do
    validate(output, unwrap_object_map(value))
  end

  def parse(%__MODULE__{} = output, value) when is_binary(value) do
    with {:ok, decoded} <- decode_json_object(value) do
      validate(output, decoded)
    end
  end

  def parse(%__MODULE__{}, value), do: {:error, output_error(:unsupported_raw_output, value)}

  @doc """
  Returns a prompt snippet that asks the model to produce the final output shape.
  """
  @spec instructions(t() | map() | nil) :: String.t() | nil
  def instructions(nil), do: nil

  def instructions(%__MODULE__{} = output) do
    schema_json =
      output
      |> json_schema()
      |> Jason.encode!(pretty: true)

    """
    Structured output:
    Return the final answer as a single JSON object that matches this JSON Schema.
    Do not wrap the JSON in Markdown fences. Do not include explanatory text outside the JSON object.

    #{schema_json}
    """
    |> String.trim()
  end

  def instructions(context) when is_map(context) do
    context
    |> runtime_output()
    |> instructions()
  end

  @doc """
  Converts an output contract to JSON Schema for provider repair calls and docs.
  """
  @spec json_schema(t()) :: map()
  def json_schema(%__MODULE__{schema_kind: :json_schema, schema: schema}), do: schema
  def json_schema(%__MODULE__{schema_kind: :zoi, schema: schema}), do: ReqLLM.Schema.to_json(schema)

  @doc false
  @spec on_before_cmd(Jido.Agent.t(), term(), t() | nil) :: {:ok, Jido.Agent.t(), term()}
  def on_before_cmd(agent, {:ai_react_start, params}, nil), do: {:ok, agent, {:ai_react_start, params}}

  def on_before_cmd(agent, {:ai_react_start, params}, %__MODULE__{} = output) do
    params =
      params
      |> attach_runtime_context(:tool_context, output)
      |> maybe_attach_existing_runtime_context(output)

    request_id = params[:request_id] || agent.state[:last_request_id]
    context = Map.get(params, :tool_context, %{}) || %{}
    agent = put_request_runtime_meta(agent, request_id, context)

    {:ok, agent, {:ai_react_start, params}}
  end

  def on_before_cmd(agent, action, _output), do: {:ok, agent, action}

  @doc false
  @spec on_after_cmd(Jido.Agent.t(), term(), [term()], t() | nil) :: {:ok, Jido.Agent.t(), [term()]}
  def on_after_cmd(agent, _action, directives, nil), do: {:ok, agent, directives}

  def on_after_cmd(agent, {:ai_react_start, %{request_id: request_id} = params}, directives, %__MODULE__{} = output)
      when is_binary(request_id) do
    context =
      params
      |> Map.get(:tool_context, %{})
      |> normalize_context(output, agent, request_id)

    cond do
      raw_mode?(context) ->
        {:ok, agent, directives}

      true ->
        {:ok, finalize_request(agent, request_id, output, context), directives}
    end
  end

  def on_after_cmd(agent, _action, directives, %__MODULE__{} = output) do
    request_id = agent.state[:last_request_id]
    context = normalize_context(%{}, output, agent, request_id)

    cond do
      not is_binary(request_id) ->
        {:ok, agent, directives}

      raw_mode?(context) ->
        {:ok, agent, directives}

      true ->
        {:ok, finalize_request(agent, request_id, output, context), directives}
    end
  end

  @doc """
  Finalizes a completed request result into structured output.
  """
  @spec finalize(Jido.Agent.t(), String.t(), t(), keyword()) :: Jido.Agent.t()
  def finalize(agent, request_id, %__MODULE__{} = output, opts \\ []) when is_binary(request_id) do
    context = Keyword.get(opts, :context, %{})
    finalize_request(agent, request_id, output, context, opts)
  end

  @doc false
  @spec attach_request_option(map(), term()) :: map()
  def attach_request_option(context, nil), do: context
  def attach_request_option(context, :raw), do: Map.put(context, @context_key, %{mode: :raw})
  def attach_request_option(context, "raw"), do: Map.put(context, @context_key, %{mode: :raw})
  def attach_request_option(context, _other), do: context

  @doc false
  @spec runtime_output(map()) :: t() | nil
  def runtime_output(context) when is_map(context) do
    case Map.get(context, @context_key) || Map.get(context, Atom.to_string(@context_key)) do
      %{output: %__MODULE__{} = output} -> output
      %__MODULE__{} = output -> output
      _other -> nil
    end
  end

  def runtime_output(_context), do: nil

  @doc false
  @spec imported_schema?(term()) :: boolean()
  def imported_schema?(%{} = schema) do
    type = Map.get(schema, "type") || Map.get(schema, :type)
    properties = Map.get(schema, "properties") || Map.get(schema, :properties)
    type in ["object", :object] and is_map(properties)
  end

  def imported_schema?(_schema), do: false

  defp finalize_request(agent, request_id, output, context, opts \\ []) do
    case Request.get_request(agent, request_id) do
      %{status: :completed, result: result} = request ->
        if get_in(request, [:meta, :jidoka_output, :applied?]) do
          agent
        else
          do_finalize_result(agent, request_id, output, context, result, opts)
        end

      _request ->
        agent
    end
  end

  defp do_finalize_result(agent, request_id, output, context, result, opts) do
    trace(output, request_id, context, :start, %{attempt: 0})

    case parse(output, result) do
      {:ok, parsed} ->
        meta = output_meta(output, :validated, result, attempt: 0, applied?: true)
        trace(output, request_id, context, :validated, %{attempt: 0})
        complete_request(agent, request_id, parsed, meta)

      {:error, reason} ->
        maybe_repair(agent, request_id, output, context, result, reason, opts)
    end
  end

  defp maybe_repair(
         agent,
         request_id,
         %{on_validation_error: :repair, retries: retries} = output,
         context,
         result,
         reason,
         opts
       )
       when retries > 0 do
    trace(output, request_id, context, :repair, %{attempt: 1})

    case repair(agent, output, context, result, reason, opts) do
      {:ok, repaired} ->
        meta = output_meta(output, :repaired, result, attempt: 1, applied?: true, validation_error: reason)
        trace(output, request_id, context, :validated, %{attempt: 1})
        complete_request(agent, request_id, repaired, meta)

      {:error, repair_reason} ->
        fail_output(agent, request_id, output, context, result, repair_reason, attempt: 1)
    end
  end

  defp maybe_repair(agent, request_id, output, context, result, reason, _opts) do
    fail_output(agent, request_id, output, context, result, reason, attempt: 0)
  end

  defp repair(agent, output, context, result, reason, opts) do
    repair_fun = Keyword.get(opts, :repair_fun) || Application.get_env(:jidoka, :output_repair_fun)

    repair_fun =
      cond do
        is_function(repair_fun, 5) ->
          repair_fun

        is_function(repair_fun, 4) ->
          fn output, agent, context, result, _reason -> repair_fun.(output, agent, context, result) end

        true ->
          &default_repair/5
      end

    with {:ok, repaired} <- repair_fun.(output, agent, context, result, reason) do
      validate(output, repaired)
    end
  rescue
    error -> {:error, output_error({:repair_exception, reason_message(error)}, result)}
  end

  defp default_repair(output, agent, context, result, reason) do
    model = Map.get(agent.state || %{}, :model)

    if is_nil(model) do
      {:error, output_error(:missing_repair_model, result)}
    else
      messages = [
        %{
          role: "system",
          content:
            "Extract a JSON object that matches the provided schema from the assistant answer. Return only the structured object."
        },
        %{role: "user", content: repair_prompt(context, result, reason)}
      ]

      llm_opts =
        context
        |> output_llm_opts()
        |> Keyword.delete(:tools)
        |> Keyword.delete(:tool_choice)
        |> Keyword.put(:stream, false)

      case ReqLLM.Generation.generate_object(model, messages, output.schema, llm_opts) do
        {:ok, response} ->
          ReqLLM.Response.unwrap_object(response, json_repair: true)

        {:error, error} ->
          {:error, output_error({:repair_failed, reason_message(error)}, result)}
      end
    end
  end

  defp repair_prompt(context, result, reason) do
    output_context =
      Map.get(context, @context_key) ||
        Map.get(context, Atom.to_string(@context_key)) ||
        %{}

    """
    Original user message:
    #{Map.get(output_context, :user_message, Map.get(output_context, "user_message", ""))}

    Assistant answer:
    #{raw_preview(result)}

    Validation error:
    #{Jidoka.format_error(reason)}
    """
  end

  defp output_llm_opts(context) do
    case Map.get(context, @context_key) do
      %{llm_opts: llm_opts} when is_list(llm_opts) -> llm_opts
      _other -> []
    end
  end

  defp complete_request(agent, request_id, parsed, meta) do
    Request.complete_request(agent, request_id, parsed, meta: %{jidoka_output: meta})
  end

  defp fail_output(agent, request_id, output, context, result, reason, opts) do
    attempt = Keyword.fetch!(opts, :attempt)
    meta = output_meta(output, :error, result, attempt: attempt, error: reason, applied?: true)
    trace(output, request_id, context, :error, %{attempt: attempt, error: Jidoka.format_error(reason)})

    agent
    |> force_request_failure(request_id, reason)
    |> put_output_meta(request_id, meta)
  end

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
      |> Map.put(:completed, true)

    %{agent | state: state}
  end

  defp put_output_meta(agent, request_id, meta) do
    state =
      update_in(agent.state, [:requests, request_id], fn
        nil ->
          %{meta: %{jidoka_output: meta}}

        request ->
          request_meta =
            request
            |> Map.get(:meta, %{})
            |> Map.put(:jidoka_output, meta)

          Map.put(request, :meta, request_meta)
      end)

    %{agent | state: state}
  end

  defp put_request_runtime_meta(agent, request_id, context) when is_binary(request_id) and is_map(context) do
    runtime_meta =
      context
      |> Map.get(@context_key, %{})
      |> normalize_runtime_output_context()
      |> Map.take([:mode, :llm_opts])

    state =
      update_in(agent.state, [:requests, request_id], fn
        nil ->
          %{meta: %{jidoka_output_runtime: runtime_meta}}

        request ->
          request_meta =
            request
            |> Map.get(:meta, %{})
            |> Map.put(:jidoka_output_runtime, runtime_meta)

          Map.put(request, :meta, request_meta)
      end)

    %{agent | state: state}
  end

  defp put_request_runtime_meta(agent, _request_id, _context), do: agent

  defp output_meta(output, status, raw, opts) do
    %{
      applied?: Keyword.get(opts, :applied?, false),
      status: status,
      schema_kind: output.schema_kind,
      retries: output.retries,
      on_validation_error: output.on_validation_error,
      attempt: Keyword.get(opts, :attempt, 0),
      raw_preview: raw_preview(raw),
      error: format_meta_error(Keyword.get(opts, :error)),
      validation_error: format_meta_error(Keyword.get(opts, :validation_error))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp raw_preview(value), do: Jidoka.Sanitize.preview(value, @raw_preview_bytes)

  defp format_meta_error(nil), do: nil
  defp format_meta_error(reason), do: Jidoka.format_error(reason)

  defp decode_json_object(value) do
    value
    |> strip_markdown_fence()
    |> Jason.decode()
    |> case do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, other} -> {:error, output_error(:expected_map, other)}
      {:error, error} -> {:error, output_error({:parse, reason_message(error)}, value)}
    end
  end

  defp strip_markdown_fence(value) do
    trimmed = String.trim(value)

    case Regex.run(~r/\A```[^\n]*\n?(.*?)\s*```\z/s, trimmed) do
      [_, inner] -> String.trim(inner)
      _other -> trimmed
    end
  end

  defp attach_runtime_context(params, key, output) do
    Map.update(params, key, output_runtime_context(output, %{}, params), fn context ->
      context
      |> Kernel.||(%{})
      |> Map.put(@context_key, output_runtime_context(output, context, params))
    end)
  end

  defp maybe_attach_existing_runtime_context(params, output) do
    if Map.has_key?(params, :runtime_context) do
      attach_runtime_context(params, :runtime_context, output)
    else
      params
    end
  end

  defp output_runtime_context(output, context, params) do
    existing = Map.get(context || %{}, @context_key, %{})

    existing
    |> normalize_runtime_output_context()
    |> Map.put(:output, output)
    |> Map.put_new(:mode, :structured)
    |> maybe_put_llm_opts(params)
    |> maybe_put_user_message(params)
  end

  defp normalize_runtime_output_context(%{} = context), do: context
  defp normalize_runtime_output_context(_other), do: %{}

  defp maybe_put_llm_opts(output_context, context) do
    case Map.get(context || %{}, :llm_opts) do
      llm_opts when is_list(llm_opts) -> Map.put(output_context, :llm_opts, llm_opts)
      _other -> output_context
    end
  end

  defp maybe_put_user_message(output_context, params) do
    case Map.get(params || %{}, :query) || Map.get(params || %{}, "query") do
      message when is_binary(message) -> Map.put(output_context, :user_message, message)
      _other -> output_context
    end
  end

  defp normalize_context(context, output, agent, request_id) when is_map(context) do
    context =
      case Map.get(context, @context_key) || Map.get(context, Atom.to_string(@context_key)) do
        %{output: %__MODULE__{}} ->
          context

        %{} = output_context ->
          Map.put(context, @context_key, Map.put(output_context, :output, output))

        _other ->
          runtime_context_from_request(agent, request_id, output)
      end

    context
    |> put_agent_id(agent)
    |> put_user_message(agent, request_id)
  end

  defp normalize_context(_context, output, agent, request_id) do
    normalize_context(%{}, output, agent, request_id)
  end

  defp runtime_context_from_request(agent, request_id, output) when is_binary(request_id) do
    output_context =
      agent
      |> get_in([Access.key(:state), :requests, request_id, :meta, :jidoka_output_runtime])
      |> normalize_runtime_output_context()
      |> Map.put(:output, output)
      |> Map.put_new(:mode, :structured)

    %{@context_key => output_context}
  end

  defp runtime_context_from_request(_agent, _request_id, output) do
    %{@context_key => %{output: output, mode: :structured}}
  end

  defp put_agent_id(context, agent) do
    Map.put_new(context, Jidoka.Trace.agent_id_key(), Map.get(agent, :id))
  end

  defp put_user_message(context, agent, request_id) when is_binary(request_id) do
    case get_in(agent.state, [:requests, request_id, :query]) do
      query when is_binary(query) ->
        Map.update(context, @context_key, %{user_message: query}, fn output_context ->
          output_context
          |> normalize_runtime_output_context()
          |> Map.put_new(:user_message, query)
        end)

      _other ->
        context
    end
  end

  defp put_user_message(context, _agent, _request_id), do: context

  defp raw_mode?(context) do
    case Map.get(context, @context_key) || Map.get(context, Atom.to_string(@context_key)) do
      %{mode: :raw} -> true
      %{mode: "raw"} -> true
      _other -> false
    end
  end

  defp schema_kind(schema) do
    cond do
      zoi_schema?(schema) -> {:ok, :zoi}
      imported_schema?(schema) -> {:ok, :json_schema}
      true -> {:error, "output schema must be a Zoi object schema or imported JSON object schema"}
    end
  end

  defp validate_schema_shape(schema, :zoi) do
    if Zoi.Type.impl_for(schema) == Zoi.Type.Zoi.Types.Map do
      :ok
    else
      {:error, "output schema must be a Zoi object/map schema"}
    end
  end

  defp validate_schema_shape(schema, :json_schema) do
    if imported_schema?(schema) do
      :ok
    else
      {:error, "imported output schema must be a JSON Schema object with properties"}
    end
  end

  defp normalize_retries(value) when is_integer(value) and value >= 0, do: {:ok, min(value, @max_retries)}

  defp normalize_retries(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_retries(integer)
      _other -> {:error, "output retries must be a non-negative integer"}
    end
  end

  defp normalize_retries(_value), do: {:error, "output retries must be a non-negative integer"}

  defp normalize_mode(value) when value in [:repair, "repair"], do: {:ok, :repair}
  defp normalize_mode(value) when value in [:error, "error"], do: {:ok, :error}
  defp normalize_mode(_value), do: {:error, "output on_validation_error must be :repair or :error"}

  defp zoi_schema?(schema), do: is_struct(schema) and not is_nil(Zoi.Type.impl_for(schema))

  defp normalize_zoi_input(%Zoi.Types.Map{fields: fields}, value) when is_map(value) do
    field_map =
      Map.new(fields, fn {field, _schema} ->
        {to_string(field), field}
      end)

    Map.new(value, fn {key, field_value} ->
      normalized_key =
        if is_binary(key) do
          Map.get(field_map, key, key)
        else
          key
        end

      nested_schema = field_schema(fields, normalized_key)
      {normalized_key, normalize_zoi_input(nested_schema, field_value)}
    end)
  end

  defp normalize_zoi_input(%Zoi.Types.Array{inner: inner}, values) when is_list(values) do
    Enum.map(values, &normalize_zoi_input(inner, &1))
  end

  defp normalize_zoi_input(%Zoi.Types.Enum{enum_type: :atom, values: values}, value) when is_binary(value) do
    Enum.find_value(values, value, fn {_label, atom_value} ->
      if Atom.to_string(atom_value) == value do
        atom_value
      end
    end)
  end

  defp normalize_zoi_input(_schema, value), do: value

  defp field_schema(fields, key) do
    Enum.find_value(fields, fn {field, schema} ->
      if field == key, do: schema
    end)
  end

  defp unwrap_object_map(%{object: object}) when is_map(object), do: object
  defp unwrap_object_map(%{"object" => object}) when is_map(object), do: object
  defp unwrap_object_map(map), do: map

  defp output_error(:expected_map, value), do: output_error(:expected_map, value, value)
  defp output_error(:unsupported_raw_output, value), do: output_error(:unsupported_raw_output, value, value)
  defp output_error({:parse, message}, value), do: output_error({:parse, message}, value, value)
  defp output_error({:schema, errors}, value), do: output_error({:schema, errors}, value, value)
  defp output_error(:missing_repair_model, value), do: output_error(:missing_repair_model, value, value)
  defp output_error({:repair_failed, message}, value), do: output_error({:repair_failed, message}, value, value)
  defp output_error({:repair_exception, message}, value), do: output_error({:repair_exception, message}, value, value)

  defp output_error(reason, value, raw) do
    Jidoka.Error.validation_error(output_error_message(reason),
      field: :output,
      value: value,
      details: %{reason: reason, raw_preview: raw_preview(raw)}
    )
  end

  defp output_error_message(:expected_map), do: "Invalid output: expected a JSON object."
  defp output_error_message(:expected_map_result), do: "Invalid output schema: expected parsing to return a map."
  defp output_error_message(:unsupported_raw_output), do: "Invalid output: unsupported model response shape."
  defp output_error_message(:missing_repair_model), do: "Invalid output: cannot repair without a model."
  defp output_error_message({:parse, message}), do: "Invalid output: could not parse JSON object. #{message}"

  defp output_error_message({:schema, errors}),
    do: "Invalid output: output did not match the configured schema. #{inspect(errors)}"

  defp output_error_message({:repair_failed, message}), do: "Invalid output repair failed. #{message}"
  defp output_error_message({:repair_exception, message}), do: "Invalid output repair failed. #{message}"

  defp trace(output, request_id, context, event, extra) do
    metadata =
      %{
        event: event,
        output: "structured_output",
        request_id: request_id,
        schema_kind: output.schema_kind,
        status: trace_status(event),
        source: :jidoka,
        category: :output,
        agent_id: Map.get(context, Jidoka.Trace.agent_id_key())
      }
      |> Map.merge(extra)

    Jidoka.Trace.emit(:output, metadata)
  end

  defp trace_status(:start), do: :running
  defp trace_status(:validated), do: :completed
  defp trace_status(:repair), do: :running
  defp trace_status(:error), do: :failed

  defp reason_message(%{__exception__: true} = error), do: Exception.message(error)
  defp reason_message(reason), do: inspect(reason, limit: 20, printable_limit: @raw_preview_bytes)
end
