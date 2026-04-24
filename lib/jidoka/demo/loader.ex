defmodule Jidoka.Demo.Loader do
  @moduledoc false

  @spec load!(:chat | :orchestrator | :kitchen_sink | :workflow) :: :ok
  def load!(:chat) do
    require_example!("chat")
  end

  def load!(:orchestrator) do
    require_example!("orchestrator")
  end

  def load!(:kitchen_sink) do
    require_example!("kitchen_sink")
  end

  def load!(:workflow) do
    require_example!("workflow")
  end

  defp require_example!(name) when is_binary(name) do
    example_root()
    |> Path.join(name)
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> sort_files()
    |> Enum.each(&require_file_unless_loaded/1)

    :ok
  end

  defp require_file_unless_loaded(path) do
    modules = modules_defined_in(path)

    if modules != [] and Enum.all?(modules, &Code.ensure_loaded?/1) do
      :ok
    else
      Code.require_file(path)
    end
  end

  defp sort_files(files) do
    files = Enum.sort(files)
    modules_by_file = Map.new(files, &{&1, modules_defined_in(&1)})

    module_to_file =
      modules_by_file
      |> Enum.flat_map(fn {file, modules} -> Enum.map(modules, &{&1, file}) end)
      |> Map.new()

    dependencies =
      Map.new(files, fn file ->
        dependency_files =
          file
          |> module_refs_in()
          |> Enum.map(&Map.get(module_to_file, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1 == file))
          |> Enum.concat(phase_dependencies(file, files))
          |> Enum.uniq()
          |> Enum.sort()

        {file, dependency_files}
      end)

    topo_sort!(dependencies, [])
  end

  defp topo_sort!(dependencies, acc) when map_size(dependencies) == 0 do
    Enum.reverse(acc)
  end

  defp topo_sort!(dependencies, acc) do
    ready =
      dependencies
      |> Enum.filter(fn {_file, deps} -> deps == [] end)
      |> Enum.map(fn {file, _deps} -> file end)
      |> Enum.sort()

    case ready do
      [] ->
        raise "cyclic or unresolved example dependencies: #{inspect(Map.keys(dependencies))}"

      _ ->
        ready_set = MapSet.new(ready)

        dependencies =
          dependencies
          |> Map.drop(ready)
          |> Map.new(fn {file, deps} ->
            {file, Enum.reject(deps, &MapSet.member?(ready_set, &1))}
          end)

        topo_sort!(dependencies, Enum.reverse(ready) ++ acc)
    end
  end

  defp phase_dependencies(file, files) do
    file_phase = phase(file)

    files
    |> Enum.filter(&(phase(&1) < file_phase))
    |> Enum.reject(&(&1 == file))
  end

  defp phase(file) do
    segments = Path.split(file)
    basename = Path.basename(file)

    cond do
      basename in ["demo.ex", "imported_demo.ex"] -> 90
      "prompts" in segments -> 10
      "tools" in segments -> 20
      "plugins" in segments -> 30
      "hooks" in segments -> 40
      "guardrails" in segments -> 50
      "subagents" in segments -> 60
      "agents" in segments -> 70
      "workflows" in segments -> 70
      true -> 15
    end
  end

  defp modules_defined_in(path) do
    path
    |> quoted_file!()
    |> collect_alias_modules(:defmodule)
    |> Enum.uniq()
  end

  defp module_refs_in(path) do
    path
    |> quoted_file!()
    |> collect_alias_modules(:ref)
    |> Enum.filter(&jidoka_example_module?/1)
    |> Enum.uniq()
  end

  defp quoted_file!(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!(file: path)
  end

  defp collect_alias_modules(ast, mode) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [module_ast, _block]} = node, acc when mode == :defmodule ->
          {node, module_ast |> modules_from_alias_ast() |> Enum.concat(acc)}

        {:__aliases__, _meta, _parts} = node, acc when mode == :ref ->
          {node, node |> modules_from_alias_ast() |> Enum.concat(acc)}

        node, acc ->
          {node, acc}
      end)

    modules
  end

  defp modules_from_alias_ast({:__aliases__, _meta, parts}) do
    parts
    |> expand_alias_parts()
    |> Enum.map(&Module.concat/1)
  end

  defp modules_from_alias_ast(_ast), do: []

  defp expand_alias_parts(parts) do
    case Enum.split_while(parts, &(&1 != :{})) do
      {_prefix, []} ->
        [parts]

      {prefix, [:{} | grouped]} ->
        grouped
        |> List.flatten()
        |> Enum.map(fn
          {:__aliases__, _meta, suffix} -> prefix ++ suffix
          suffix when is_atom(suffix) -> prefix ++ [suffix]
        end)
    end
  end

  defp jidoka_example_module?(module) do
    module
    |> Module.split()
    |> Enum.take(2)
    |> Kernel.==(["Jidoka", "Examples"])
  end

  defp example_root do
    Path.expand("../../../examples", __DIR__)
  end
end
