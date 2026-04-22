defmodule Moto.ImportedAgent.Codec do
  @moduledoc false

  alias Moto.ImportedAgent.Spec

  @spec decode(binary(), :auto | :json | :yaml | term()) :: {:ok, map()} | {:error, String.t()}
  def decode(source, :auto) when is_binary(source) do
    source
    |> detect_source_format()
    |> then(&decode(source, &1))
  end

  def decode(source, :json) when is_binary(source) do
    case Jason.decode(source) do
      {:ok, %{} = attrs} ->
        {:ok, attrs}

      {:ok, other} ->
        {:error, "imported Moto agent specs must decode to an object, got: #{inspect(other)}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  def decode(source, :yaml) when is_binary(source) do
    case YamlElixir.read_from_string(source) do
      {:ok, %{} = attrs} ->
        {:ok, attrs}

      {:ok, other} ->
        {:error, "imported Moto agent specs must decode to a map, got: #{inspect(other)}"}

      {:error, error} ->
        {:error, format_error(error)}
    end
  end

  def decode(_source, format),
    do: {:error, "unsupported format #{inspect(format)}; expected :json, :yaml, or :auto"}

  @spec detect_file_format(Path.t(), :json | :yaml | nil | term()) ::
          {:ok, :json | :yaml} | {:error, String.t()}
  def detect_file_format(_path, format) when format in [:json, :yaml], do: {:ok, format}

  def detect_file_format(path, nil) when is_binary(path) do
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

  def detect_file_format(_path, other),
    do: {:error, "unsupported format #{inspect(other)}; expected :json or :yaml"}

  @spec expand_skill_paths(map(), Path.t()) :: map()
  def expand_skill_paths(%{} = attrs, base_dir) when is_binary(base_dir) do
    skill_paths = Map.get(attrs, "skill_paths", Map.get(attrs, :skill_paths, []))

    expanded_paths =
      Enum.map(skill_paths, fn
        path when is_binary(path) -> Path.expand(path, base_dir)
        other -> other
      end)

    attrs
    |> maybe_put("skill_paths", expanded_paths)
    |> maybe_put(:skill_paths, expanded_paths)
  end

  @spec encode(Spec.t(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def encode(%Spec{} = spec, opts \\ []) do
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

  defp detect_source_format(source) do
    case String.trim_leading(source) do
      <<"{"::utf8, _::binary>> -> :json
      _ -> :yaml
    end
  end

  defp maybe_put(map, key, value) do
    if Map.has_key?(map, key), do: Map.put(map, key, value), else: map
  end

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
      "context:",
      encode_yaml_context(spec.context),
      "memory:",
      encode_yaml_memory(spec.memory),
      "tools:",
      encode_yaml_tools(spec.tools),
      "skills:",
      encode_yaml_skills(spec.skills),
      "skill_paths:",
      encode_yaml_skill_paths(spec.skill_paths),
      "mcp_tools:",
      encode_yaml_mcp_tools(spec.mcp_tools),
      "subagents:",
      encode_yaml_subagents(spec.subagents),
      "plugins:",
      encode_yaml_plugins(spec.plugins),
      "hooks:",
      encode_yaml_hooks(spec.hooks),
      "guardrails:",
      encode_yaml_guardrails(spec.guardrails)
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp encode_yaml_tools([]), do: "  []"
  defp encode_yaml_tools(tools), do: Enum.map_join(tools, "\n", &"  - #{Jason.encode!(&1)}")

  defp encode_yaml_skills([]), do: "  []"
  defp encode_yaml_skills(skills), do: Enum.map_join(skills, "\n", &"  - #{Jason.encode!(&1)}")

  defp encode_yaml_skill_paths([]), do: "  []"

  defp encode_yaml_skill_paths(paths) do
    Enum.map_join(paths, "\n", &"  - #{Jason.encode!(&1)}")
  end

  defp encode_yaml_mcp_tools([]), do: "  []"

  defp encode_yaml_mcp_tools(entries) do
    Enum.map_join(entries, "\n", fn entry ->
      endpoint = entry["endpoint"] || entry[:endpoint]
      prefix = entry["prefix"] || entry[:prefix]

      ["  - endpoint: #{Jason.encode!(endpoint)}" | maybe_yaml_line("prefix", prefix, "    ")]
      |> Enum.join("\n")
    end)
  end

  defp encode_yaml_subagents([]), do: "  []"

  defp encode_yaml_subagents(subagents) do
    Enum.map_join(subagents, "\n", fn subagent ->
      lines =
        [
          "  - agent: #{Jason.encode!(subagent["agent"] || subagent[:agent])}"
        ] ++
          maybe_yaml_line("as", subagent["as"] || subagent[:as]) ++
          maybe_yaml_line("description", subagent["description"] || subagent[:description]) ++
          ["    target: #{Jason.encode!(subagent["target"] || subagent[:target])}"] ++
          maybe_yaml_line("timeout_ms", subagent["timeout_ms"] || subagent[:timeout_ms], "    ") ++
          maybe_yaml_line("result", subagent["result"] || subagent[:result], "    ") ++
          maybe_yaml_forward_context(subagent["forward_context"] || subagent[:forward_context]) ++
          maybe_yaml_line("peer_id", subagent["peer_id"] || subagent[:peer_id], "    ") ++
          maybe_yaml_line(
            "peer_id_context_key",
            subagent["peer_id_context_key"] || subagent[:peer_id_context_key],
            "    "
          )

      Enum.join(lines, "\n")
    end)
  end

  defp maybe_yaml_forward_context(nil), do: []
  defp maybe_yaml_forward_context("public"), do: ["    forward_context: \"public\""]
  defp maybe_yaml_forward_context("none"), do: ["    forward_context: \"none\""]

  defp maybe_yaml_forward_context(%{} = forward_context) do
    mode = forward_context["mode"] || forward_context[:mode]
    keys = forward_context["keys"] || forward_context[:keys]

    ["    forward_context:", "      mode: #{Jason.encode!(mode)}"] ++
      case keys do
        nil -> []
        keys -> ["      keys: #{Jason.encode!(keys)}"]
      end
  end

  defp maybe_yaml_forward_context(other), do: ["    forward_context: #{Jason.encode!(other)}"]

  defp encode_yaml_context(context) when context == %{}, do: "  {}"

  defp encode_yaml_context(context) when is_map(context) do
    Enum.map_join(context, "\n", fn {key, value} ->
      "  #{yaml_key(key)}: #{Jason.encode!(value)}"
    end)
  end

  defp encode_yaml_plugins([]), do: "  []"
  defp encode_yaml_plugins(plugins), do: Enum.map_join(plugins, "\n", &"  - #{Jason.encode!(&1)}")

  defp encode_yaml_memory(nil), do: "  null"

  defp encode_yaml_memory(%{namespace: :per_agent} = memory) do
    [
      "  mode: #{Jason.encode!(Atom.to_string(memory.mode))}",
      "  namespace: \"per_agent\"",
      "  capture: #{Jason.encode!(Atom.to_string(memory.capture))}",
      "  retrieve:",
      "    limit: #{memory.retrieve.limit}",
      "  inject: #{Jason.encode!(Atom.to_string(memory.inject))}"
    ]
    |> Enum.join("\n")
  end

  defp encode_yaml_memory(%{namespace: {:shared, shared_namespace}} = memory) do
    [
      "  mode: #{Jason.encode!(Atom.to_string(memory.mode))}",
      "  namespace: \"shared\"",
      "  shared_namespace: #{Jason.encode!(shared_namespace)}",
      "  capture: #{Jason.encode!(Atom.to_string(memory.capture))}",
      "  retrieve:",
      "    limit: #{memory.retrieve.limit}",
      "  inject: #{Jason.encode!(Atom.to_string(memory.inject))}"
    ]
    |> Enum.join("\n")
  end

  defp encode_yaml_memory(%{namespace: {:context, key}} = memory) do
    [
      "  mode: #{Jason.encode!(Atom.to_string(memory.mode))}",
      "  namespace: \"context\"",
      "  context_namespace_key: #{Jason.encode!(key)}",
      "  capture: #{Jason.encode!(Atom.to_string(memory.capture))}",
      "  retrieve:",
      "    limit: #{memory.retrieve.limit}",
      "  inject: #{Jason.encode!(Atom.to_string(memory.inject))}"
    ]
    |> Enum.join("\n")
  end

  defp encode_yaml_hooks(hooks) do
    Enum.map_join([:before_turn, :after_turn, :on_interrupt], "\n", fn stage ->
      hook_names = Map.get(hooks, stage, [])

      [
        "  #{stage}:",
        if(hook_names == [],
          do: "    []",
          else: Enum.map_join(hook_names, "\n", &"    - #{Jason.encode!(&1)}")
        )
      ]
      |> Enum.join("\n")
    end)
  end

  defp encode_yaml_guardrails(guardrails) do
    Enum.map_join([:input, :output, :tool], "\n", fn stage ->
      guardrail_names = Map.get(guardrails, stage, [])

      case guardrail_names do
        [] ->
          "  #{stage}: []"

        names ->
          ["  #{stage}:" | Enum.map(names, &"    - #{Jason.encode!(&1)}")]
          |> Enum.join("\n")
      end
    end)
  end

  defp yaml_key(key) when is_atom(key), do: Atom.to_string(key)
  defp yaml_key(key) when is_binary(key), do: key

  defp maybe_yaml_line(key, value, indent \\ "    ")
  defp maybe_yaml_line(_key, nil, _indent), do: []
  defp maybe_yaml_line(_key, "", _indent), do: []

  defp maybe_yaml_line(key, value, indent) do
    ["#{indent}#{key}: #{Jason.encode!(value)}"]
  end
end
