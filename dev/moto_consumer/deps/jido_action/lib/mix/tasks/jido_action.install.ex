# covers: jido_action.scaffolding.install_and_generators
if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.JidoAction.Install do
    @shortdoc "Installs and configures jido_action in your project"

    @moduledoc """
    #{@shortdoc}

    ## Usage

        mix jido_action.install

    Or via igniter:

        mix igniter.install jido_action

    ## Options

    - `--example` - Generate an example action to get started

    ## What this task does

    1. Adds default configuration for jido_action to `config/config.exs`
    2. Optionally generates an example action module
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Config

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_action,
        adds_deps: [],
        installs: [],
        example: "mix jido_action.install --example",
        only: nil,
        positional: [],
        schema: [
          example: :boolean
        ],
        defaults: [
          example: false
        ],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def installer?, do: true

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options

      igniter
      |> add_default_config()
      |> maybe_generate_example(opts[:example])
    end

    defp add_default_config(igniter) do
      igniter
      |> Config.configure_new(
        "config.exs",
        :jido_action,
        [:default_timeout],
        30_000
      )
      |> Config.configure_new(
        "config.exs",
        :jido_action,
        [:default_max_retries],
        1
      )
      |> Config.configure_new(
        "config.exs",
        :jido_action,
        [:default_backoff],
        250
      )
    end

    defp maybe_generate_example(igniter, true) do
      app_name = Igniter.Project.Application.app_name(igniter)
      module_name = Module.concat([Macro.camelize(to_string(app_name)), Actions, Example])

      Igniter.compose_task(igniter, "jido_action.gen.action", [inspect(module_name)])
    end

    defp maybe_generate_example(igniter, _false), do: igniter
  end
else
  defmodule Mix.Tasks.JidoAction.Install do
    @shortdoc "Requires :igniter dependency"

    @moduledoc """
    #{@shortdoc}

    Add `{:igniter, "~> 0.7", only: [:dev, :test]}` to your deps to use this task.
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.raise("""
      mix jido_action.install requires the :igniter dependency.

      Add to your mix.exs:

          {:igniter, "~> 0.7", only: [:dev, :test]}
      """)
    end
  end
end
