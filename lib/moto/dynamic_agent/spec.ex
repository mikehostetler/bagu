defmodule Moto.DynamicAgent.Spec do
  @moduledoc false

  @name_schema [
    Zoi.string()
    |> Zoi.trim()
    |> Zoi.min(1)
    |> Zoi.max(64)
    |> Zoi.regex(~r/^[A-Za-z0-9][A-Za-z0-9_-]*$/)
  ]

  @prompt_schema [
    Zoi.string()
    |> Zoi.min(1)
    |> Zoi.max(50_000)
  ]

  @tool_name_schema Zoi.string()
                    |> Zoi.trim()
                    |> Zoi.min(1)
                    |> Zoi.max(128)
                    |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @plugin_name_schema Zoi.string()
                      |> Zoi.trim()
                      |> Zoi.min(1)
                      |> Zoi.max(128)
                      |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @hook_name_schema Zoi.string()
                    |> Zoi.trim()
                    |> Zoi.min(1)
                    |> Zoi.max(128)
                    |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @default_hooks %{before_turn: [], after_turn: [], on_interrupt: []}

  @model_map_schema Zoi.object(
                      %{
                        provider:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.max(64),
                        id:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.max(256),
                        base_url:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.max(2_048)
                          |> Zoi.optional()
                      },
                      coerce: true,
                      unrecognized_keys: :error
                    )

  @hooks_schema Zoi.object(
                  %{
                    before_turn: Zoi.list(@hook_name_schema) |> Zoi.default([]),
                    after_turn: Zoi.list(@hook_name_schema) |> Zoi.default([]),
                    on_interrupt: Zoi.list(@hook_name_schema) |> Zoi.default([])
                  },
                  coerce: true,
                  unrecognized_keys: :error
                )

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: hd(@name_schema),
              system_prompt: hd(@prompt_schema),
              model:
                Zoi.union([
                  Zoi.string() |> Zoi.trim() |> Zoi.min(1) |> Zoi.max(256),
                  @model_map_schema
                ]),
              tools: Zoi.list(@tool_name_schema) |> Zoi.default([]),
              plugins: Zoi.list(@plugin_name_schema) |> Zoi.default([]),
              hooks: @hooks_schema |> Zoi.default(@default_hooks)
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type model_input ::
          atom()
          | String.t()
          | %{
              required(:provider) => String.t(),
              required(:id) => String.t(),
              optional(:base_url) => String.t()
            }
  @type t :: %__MODULE__{
          name: String.t(),
          system_prompt: String.t(),
          model: model_input(),
          tools: [String.t()],
          plugins: [String.t()],
          hooks: %{
            before_turn: [String.t()],
            after_turn: [String.t()],
            on_interrupt: [String.t()]
          }
        }

  @enforce_keys [:name, :system_prompt, :model]
  defstruct [:name, :system_prompt, :model, tools: [], plugins: [], hooks: @default_hooks]

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = spec, opts) do
    with {:ok, spec} <- validate_tools(spec, Keyword.get(opts, :available_tools, %{})),
         {:ok, spec} <- validate_plugins(spec, Keyword.get(opts, :available_plugins, %{})) do
      validate_hooks(spec, Keyword.get(opts, :available_hooks, %{}))
    end
  end

  def new(attrs, opts) when is_map(attrs) do
    with {:ok, spec} <- Zoi.parse(@schema, attrs),
         {:ok, normalized_model} <- normalize_model(spec.model),
         :ok <- validate_model(normalized_model),
         {:ok, normalized_spec} <-
           validate_tools(
             %{spec | model: normalized_model},
             Keyword.get(opts, :available_tools, %{})
           ),
         {:ok, normalized_spec} <-
           validate_plugins(
             normalized_spec,
             Keyword.get(opts, :available_plugins, %{})
           ),
         {:ok, normalized_spec} <-
           validate_hooks(
             normalized_spec,
             Keyword.get(opts, :available_hooks, %{})
           ) do
      {:ok, normalized_spec}
    else
      {:error, [%Zoi.Error{} | _] = errors} ->
        {:error, format_zoi_errors(errors)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def new(other, _opts),
    do: {:error, "dynamic Moto agent specs must be maps, got: #{inspect(other)}"}

  @spec to_external_map(t()) :: map()
  def to_external_map(%__MODULE__{} = spec) do
    %{
      "name" => spec.name,
      "model" => externalize_model(spec.model),
      "system_prompt" => spec.system_prompt,
      "tools" => spec.tools,
      "plugins" => spec.plugins,
      "hooks" => spec.hooks
    }
  end

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = spec) do
    spec
    |> to_external_map()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_model(model) when is_binary(model) do
    trimmed = String.trim(model)

    cond do
      trimmed == "" ->
        {:error, "model must not be empty"}

      String.contains?(trimmed, ":") ->
        {:ok, trimmed}

      true ->
        case alias_atom(trimmed) do
          {:ok, alias_name} ->
            {:ok, alias_name}

          :error ->
            {:error,
             "model must be a known alias string like \"fast\" or a direct provider:model string"}
        end
    end
  end

  defp normalize_model(%{} = model) do
    normalized =
      model
      |> Map.take([:provider, :id, :base_url])
      |> Enum.reduce(%{}, fn
        {:base_url, nil}, acc -> acc
        {key, value}, acc when is_binary(value) -> Map.put(acc, key, String.trim(value))
        {key, value}, acc -> Map.put(acc, key, value)
      end)

    {:ok, normalized}
  end

  defp validate_model(model) do
    model
    |> Moto.model()
    |> ReqLLM.model()
    |> case do
      {:ok, _model} -> :ok
      {:error, reason} -> {:error, format_model_error(reason)}
    end
  end

  defp alias_atom(name) do
    (Map.keys(Moto.model_aliases()) ++ Map.keys(Jido.AI.model_aliases()))
    |> Enum.uniq()
    |> Enum.find_value(:error, fn alias_name ->
      if Atom.to_string(alias_name) == name, do: {:ok, alias_name}, else: false
    end)
  end

  defp externalize_model(model) when is_atom(model), do: Atom.to_string(model)
  defp externalize_model(model), do: model

  defp validate_tools(%__MODULE__{} = spec, available_tools) when is_map(available_tools) do
    cond do
      Enum.uniq(spec.tools) != spec.tools ->
        {:error, "tools must be unique"}

      spec.tools == [] ->
        {:ok, spec}

      map_size(available_tools) == 0 ->
        {:error, "tools require an available_tools registry when importing Moto agents"}

      true ->
        case Moto.Tool.resolve_tool_names(spec.tools, available_tools) do
          {:ok, _tool_modules} -> {:ok, spec}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_plugins(%__MODULE__{} = spec, available_plugins) when is_map(available_plugins) do
    cond do
      Enum.uniq(spec.plugins) != spec.plugins ->
        {:error, "plugins must be unique"}

      spec.plugins == [] ->
        {:ok, spec}

      map_size(available_plugins) == 0 ->
        {:error, "plugins require an available_plugins registry when importing Moto agents"}

      true ->
        case Moto.Plugin.resolve_plugin_names(spec.plugins, available_plugins) do
          {:ok, _plugin_modules} -> {:ok, spec}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_hooks(%__MODULE__{} = spec, available_hooks) when is_map(available_hooks) do
    cond do
      not hooks_unique?(spec.hooks) ->
        {:error, "hook names must be unique within each stage"}

      hooks_empty?(spec.hooks) ->
        {:ok, spec}

      map_size(available_hooks) == 0 ->
        {:error, "hooks require an available_hooks registry when importing Moto agents"}

      true ->
        spec.hooks
        |> Enum.reduce_while({:ok, spec}, fn {_stage, hook_names}, {:ok, spec_acc} ->
          case Moto.Hook.resolve_hook_names(hook_names, available_hooks) do
            {:ok, _hook_modules} -> {:cont, {:ok, spec_acc}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp format_model_error(reason) when is_binary(reason), do: reason

  defp format_model_error(%{message: message}) when is_binary(message),
    do: message

  defp format_model_error(reason), do: inspect(reason)

  defp hooks_unique?(hooks) do
    Enum.all?(hooks, fn {_stage, hook_names} -> Enum.uniq(hook_names) == hook_names end)
  end

  defp hooks_empty?(hooks) do
    Enum.all?(hooks, fn {_stage, hook_names} -> hook_names == [] end)
  end

  defp format_zoi_errors(errors) do
    errors
    |> Zoi.treefy_errors()
    |> inspect(pretty: true)
  end
end
