# covers: jido_action.scaffolding.install_and_generators
if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.JidoAction.Gen.Action do
    @shortdoc "Generates a Jido Action module"

    @moduledoc """
    #{@shortdoc}

    ## Usage

        mix jido_action.gen.action MyApp.Actions.FetchWeather

    ## Options

    - `--no-test` - Skip generating the test file

    ## Generated Files

    This task generates:

    1. An action module at `lib/my_app/actions/fetch_weather.ex`
    2. A test file at `test/my_app/actions/fetch_weather_test.exs` (unless `--no-test`)

    ## Example

        mix jido_action.gen.action MyApp.Actions.SendEmail

    Generates:

    ```elixir
    defmodule MyApp.Actions.SendEmail do
      use Jido.Action,
        name: "send_email",
        description: "TODO: Add description",
        schema: []

      @impl true
      def run(_params, _context) do
        {:ok, %{}}
      end
    end
    ```
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_action,
        adds_deps: [],
        installs: [],
        example: "mix jido_action.gen.action MyApp.Actions.FetchWeather",
        only: nil,
        positional: [:module_name],
        schema: [
          no_test: :boolean
        ],
        defaults: [
          no_test: false
        ],
        aliases: [],
        required: [:module_name]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options
      [module_name_string] = igniter.args.positional.module_name

      module_name = Igniter.Project.Module.parse(module_name_string)
      action_name = derive_action_name(module_name)

      igniter
      |> generate_action_module(module_name, action_name)
      |> maybe_generate_test(module_name, action_name, opts[:no_test])
    end

    defp derive_action_name(module_name) do
      module_name
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end

    defp generate_action_module(igniter, module_name, action_name) do
      contents = """
      defmodule #{inspect(module_name)} do
        use Jido.Action,
          name: "#{action_name}",
          description: "TODO: Add description",
          schema: []

        @impl true
        def run(_params, _context) do
          {:ok, %{}}
        end
      end
      """

      Igniter.Project.Module.create_module(igniter, module_name, contents)
    end

    defp maybe_generate_test(igniter, _module_name, _action_name, true), do: igniter

    defp maybe_generate_test(igniter, module_name, action_name, _no_test) do
      test_module_name = Module.concat(module_name, Test)

      test_contents = """
      defmodule #{inspect(test_module_name)} do
        use ExUnit.Case, async: true

        alias #{inspect(module_name)}

        describe "#{action_name}/run" do
          test "runs successfully" do
            assert {:ok, result} = #{inspect(module_name)}.run(%{}, %{})
            assert is_map(result)
          end
        end
      end
      """

      Igniter.Project.Module.create_module(
        igniter,
        test_module_name,
        test_contents,
        location: :test
      )
    end
  end
else
  defmodule Mix.Tasks.JidoAction.Gen.Action do
    @shortdoc "Requires :igniter dependency"

    @moduledoc """
    #{@shortdoc}

    Add `{:igniter, "~> 0.7", only: [:dev, :test]}` to your deps to use this task.
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.raise("""
      mix jido_action.gen.action requires the :igniter dependency.

      Add to your mix.exs:

          {:igniter, "~> 0.7", only: [:dev, :test]}
      """)
    end
  end
end
