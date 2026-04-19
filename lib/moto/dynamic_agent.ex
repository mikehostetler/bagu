defmodule Moto.DynamicAgent do
  @moduledoc false

  alias Moto.DynamicAgent.Spec

  @enforce_keys [:spec, :runtime_module, :tool_modules, :plugin_modules]
  defstruct [:spec, :runtime_module, :tool_modules, :plugin_modules]

  @type t :: %__MODULE__{
          spec: Spec.t(),
          runtime_module: module(),
          tool_modules: [module()],
          plugin_modules: [module()]
        }

  @spec import(map() | binary() | Spec.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def import(source, opts \\ [])

  def import(%Spec{} = spec, opts) do
    with {:ok, tool_registry} <- available_tool_registry(opts),
         {:ok, plugin_registry} <- available_plugin_registry(opts),
         {:ok, validated_spec} <-
           Spec.new(spec, available_tools: tool_registry, available_plugins: plugin_registry) do
      build(validated_spec, tool_registry, plugin_registry)
    end
  end

  def import(source, opts) when is_map(source) do
    with {:ok, tool_registry} <- available_tool_registry(opts),
         {:ok, plugin_registry} <- available_plugin_registry(opts),
         {:ok, spec} <-
           Spec.new(source, available_tools: tool_registry, available_plugins: plugin_registry) do
      build(spec, tool_registry, plugin_registry)
    end
  end

  def import(source, opts) when is_binary(source) do
    with {:ok, attrs} <- decode(source, Keyword.get(opts, :format, :auto)),
         {:ok, tool_registry} <- available_tool_registry(opts),
         {:ok, plugin_registry} <- available_plugin_registry(opts),
         {:ok, spec} <-
           Spec.new(attrs, available_tools: tool_registry, available_plugins: plugin_registry) do
      build(spec, tool_registry, plugin_registry)
    end
  end

  def import(other, _opts),
    do: {:error, "cannot import Moto agent from #{inspect(other)}"}

  @spec import_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def import_file(path, opts \\ []) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, format} <- detect_file_format(path, Keyword.get(opts, :format)),
         {:ok, agent} <- __MODULE__.import(contents, Keyword.put(opts, :format, format)) do
      {:ok, agent}
    else
      {:error, :enoent} ->
        {:error, "could not read agent spec file: #{path}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec start_link(t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_link(%__MODULE__{runtime_module: runtime_module}, opts \\ []) do
    Moto.Runtime.start_agent(runtime_module, opts)
  end

  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{spec: spec}, opts \\ []) do
    case Keyword.get(opts, :format, :json) do
      :json ->
        {:ok, Jason.encode!(Spec.to_external_map(spec), pretty: true)}

      :yaml ->
        {:ok, encode_yaml(spec)}

      other ->
        {:error, "unsupported format #{inspect(other)}; expected :json or :yaml"}
    end
  end

  @spec format_error(term()) :: String.t()
  def format_error(reason) when is_binary(reason), do: reason
  def format_error(%{message: message}) when is_binary(message), do: message
  def format_error(reason), do: inspect(reason)

  defp build(%Spec{} = spec, tool_registry, plugin_registry) do
    with {:ok, direct_tool_modules} <- Moto.Tool.resolve_tool_names(spec.tools, tool_registry),
         {:ok, plugin_modules} <- Moto.Plugin.resolve_plugin_names(spec.plugins, plugin_registry),
         {:ok, plugin_tool_modules} <- Moto.Plugin.plugin_actions(plugin_modules),
         tool_modules = direct_tool_modules ++ plugin_tool_modules,
         {:ok, _tool_names} <- Moto.Tool.action_names(tool_modules),
         {:ok, runtime_module} <- ensure_runtime_module(spec, tool_modules, plugin_modules) do
      {:ok,
       %__MODULE__{
         spec: spec,
         runtime_module: runtime_module,
         tool_modules: tool_modules,
         plugin_modules: plugin_modules
       }}
    end
  end

  defp decode(source, :auto) do
    source
    |> detect_source_format()
    |> then(&decode(source, &1))
  end

  defp decode(source, :json) do
    case Jason.decode(source) do
      {:ok, %{} = attrs} ->
        {:ok, attrs}

      {:ok, other} ->
        {:error, "dynamic Moto agent specs must decode to an object, got: #{inspect(other)}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp decode(source, :yaml) do
    case YamlElixir.read_from_string(source) do
      {:ok, %{} = attrs} ->
        {:ok, attrs}

      {:ok, other} ->
        {:error, "dynamic Moto agent specs must decode to a map, got: #{inspect(other)}"}

      {:error, error} ->
        {:error, format_error(error)}
    end
  end

  defp decode(_source, format),
    do: {:error, "unsupported format #{inspect(format)}; expected :json, :yaml, or :auto"}

  defp detect_source_format(source) do
    case String.trim_leading(source) do
      <<"{"::utf8, _::binary>> -> :json
      _ -> :yaml
    end
  end

  defp detect_file_format(_path, format) when format in [:json, :yaml], do: {:ok, format}

  defp detect_file_format(path, nil) do
    case Path.extname(path) do
      ".json" ->
        {:ok, :json}

      ".yaml" ->
        {:ok, :yaml}

      ".yml" ->
        {:ok, :yaml}

      ext ->
        {:error,
         "unsupported agent spec extension #{inspect(ext)}; expected .json, .yaml, or .yml"}
    end
  end

  defp detect_file_format(_path, other),
    do: {:error, "unsupported format #{inspect(other)}; expected :json or :yaml"}

  defp ensure_runtime_module(%Spec{} = spec, tool_modules, plugin_modules) do
    runtime_plugins = runtime_plugins(plugin_modules)
    runtime_module = generated_module(spec, tool_modules, runtime_plugins)

    if Code.ensure_loaded?(runtime_module) do
      {:ok, runtime_module}
    else
      create_runtime_module(runtime_module, spec, tool_modules, runtime_plugins)
    end
  end

  defp generated_module(%Spec{} = spec, tool_modules, runtime_plugins) do
    suffix =
      %{
        spec: Spec.to_external_map(spec),
        tools: Enum.map(tool_modules, &inspect/1),
        plugins: Enum.map(runtime_plugins, &inspect/1)
      }
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)
      |> String.upcase()

    Module.concat([__MODULE__, Generated, "Runtime#{suffix}"])
  end

  defp create_runtime_module(runtime_module, %Spec{} = spec, tool_modules, runtime_plugins) do
    quoted =
      quote location: :keep do
        use Jido.AI.Agent,
          name: unquote(spec.name),
          system_prompt: unquote(spec.system_prompt),
          model: unquote(Macro.escape(spec.model)),
          tools: unquote(Macro.escape(tool_modules)),
          plugins: unquote(Macro.escape(runtime_plugins))
      end

    case Module.create(runtime_module, quoted, Macro.Env.location(__ENV__)) do
      {:module, ^runtime_module, _binary, _term} ->
        {:ok, runtime_module}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError] ->
      if Code.ensure_loaded?(runtime_module) do
        {:ok, runtime_module}
      else
        {:error, error}
      end
  end

  defp available_tool_registry(opts) do
    opts
    |> Keyword.get(:available_tools, [])
    |> Moto.Tool.normalize_available_tools()
  end

  defp available_plugin_registry(opts) do
    opts
    |> Keyword.get(:available_plugins, [])
    |> Moto.Plugin.normalize_available_plugins()
  end

  defp runtime_plugins(plugin_modules), do: [Moto.Plugins.RuntimeCompat | plugin_modules]

  defp encode_yaml(%Spec{} = spec) do
    model_yaml =
      case Spec.to_external_map(spec)["model"] do
        model when is_binary(model) ->
          "model: #{Jason.encode!(model)}"

        %{} = model ->
          lines =
            model
            |> Enum.map(fn {key, value} -> "  #{key}: #{Jason.encode!(value)}" end)

          Enum.join(["model:" | lines], "\n")
      end

    prompt_block =
      spec.system_prompt
      |> String.split("\n", trim: false)
      |> Enum.map_join("\n", &"  #{&1}")

    [
      "name: #{Jason.encode!(spec.name)}",
      model_yaml,
      "system_prompt: |-",
      prompt_block,
      "tools:",
      encode_yaml_tools(spec.tools),
      "plugins:",
      encode_yaml_plugins(spec.plugins)
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp encode_yaml_tools([]), do: "  []"
  defp encode_yaml_tools(tools), do: Enum.map_join(tools, "\n", &"  - #{Jason.encode!(&1)}")

  defp encode_yaml_plugins([]), do: "  []"
  defp encode_yaml_plugins(plugins), do: Enum.map_join(plugins, "\n", &"  - #{Jason.encode!(&1)}")
end
