defmodule Jidoka.Demo do
  @moduledoc false

  alias Jidoka.Demo.Loader

  @builtin_demos %{
    "chat" => %{loader: :chat, module: Jidoka.Examples.Chat.Demo},
    "imported" => %{loader: :chat, module: Jidoka.Examples.Chat.ImportedDemo},
    "trace" => %{loader: :trace, module: Jidoka.Examples.Trace.Demo},
    "workflow" => %{loader: :workflow, module: Jidoka.Examples.Workflow.Demo},
    "structured_output" => %{loader: :structured_output, module: Jidoka.Examples.StructuredOutput.Demo},
    "orchestrator" => %{loader: :orchestrator, module: Jidoka.Examples.Orchestrator.Demo},
    "kitchen_sink" => %{loader: :kitchen_sink, module: Jidoka.Examples.KitchenSink.Demo}
  }

  @doc false
  @spec names() :: [String.t()]
  def names do
    @builtin_demos
    |> Map.keys()
    |> Kernel.++(example_names())
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc false
  @spec run(String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def run(name, argv) when is_binary(name) and is_list(argv) do
    with {:ok, module} <- load(name) do
      apply(module, :main, [argv])
    end
  end

  @doc false
  @spec load(String.t()) :: {:ok, module()} | {:error, String.t()}
  def load(name) when is_binary(name) do
    case demo_for(name) do
      {:ok, demo} ->
        Loader.load!(demo.loader)

        if Code.ensure_loaded?(demo.module) do
          {:ok, demo.module}
        else
          {:error, "demo #{inspect(name)} did not define #{inspect(demo.module)}."}
        end

      :error ->
        unknown_demo(name)
    end
  end

  @doc false
  @spec preload(String.t()) :: :ok | {:error, String.t()}
  def preload(name) when is_binary(name) do
    case demo_for(name) do
      {:ok, demo} ->
        demo
        |> Map.get(:preload, [])
        |> Enum.each(&Loader.load!/1)

        :ok

      :error ->
        unknown_demo(name)
    end
  end

  defp unknown_demo(name) do
    {:error, "unknown demo #{inspect(name)}. Expected #{Enum.map_join(names(), ", ", &"`#{&1}`")}."}
  end

  defp demo_for(name) do
    case Map.fetch(@builtin_demos, name) do
      {:ok, demo} -> {:ok, demo}
      :error -> dynamic_demo_for(name)
    end
  end

  defp dynamic_demo_for(name) do
    if name in example_names() do
      {:ok, %{loader: name, module: demo_module(name)}}
    else
      :error
    end
  end

  defp demo_module(name) do
    Module.concat([Jidoka, Examples, Macro.camelize(name), Demo])
  end

  defp example_names do
    example_root()
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(&File.exists?(Path.join(&1, "demo.ex")))
    |> Enum.map(&Path.basename/1)
  end

  defp example_root do
    Path.expand("../../examples", __DIR__)
  end
end
