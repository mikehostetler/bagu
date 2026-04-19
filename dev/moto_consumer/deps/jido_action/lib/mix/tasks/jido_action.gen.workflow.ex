# covers: jido_action.scaffolding.install_and_generators
if Code.ensure_loaded?(Igniter.Mix.Task) do
  defmodule Mix.Tasks.JidoAction.Gen.Workflow do
    @shortdoc "Generates a Jido Workflow using ActionPlan"

    @moduledoc """
    #{@shortdoc}

    ## Usage

        mix jido_action.gen.workflow MyApp.Workflows.OrderPipeline --steps=validate,process,notify

    ## Options

    - `--steps` - Comma-separated list of step names (required)
    - `--no-test` - Skip generating the test file

    ## Generated Files

    This task generates:

    1. A workflow module at `lib/my_app/workflows/order_pipeline.ex`
    2. A test file at `test/my_app/workflows/order_pipeline_test.exs` (unless `--no-test`)

    ## Example

        mix jido_action.gen.workflow MyApp.Workflows.OrderPipeline --steps=validate,process,notify

    Generates:

    ```elixir
    defmodule MyApp.Workflows.OrderPipeline do
      use Jido.Tools.ActionPlan,
        name: "order_pipeline",
        description: "TODO: Add description",
        schema: []

      alias Jido.Plan

      @impl Jido.Tools.ActionPlan
      def build(_params, context) do
        Plan.new(context: context)
        |> Plan.add(:validate, MyApp.Actions.Validate)
        |> Plan.add(:process, MyApp.Actions.Process, depends_on: :validate)
        |> Plan.add(:notify, MyApp.Actions.Notify, depends_on: :process)
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
        example:
          "mix jido_action.gen.workflow MyApp.Workflows.OrderPipeline --steps=validate,process,notify",
        only: nil,
        positional: [:module_name],
        schema: [
          steps: :string,
          no_test: :boolean
        ],
        defaults: [
          no_test: false
        ],
        aliases: [],
        required: [:module_name, :steps]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options
      [module_name_string] = igniter.args.positional.module_name

      module_name = Igniter.Project.Module.parse(module_name_string)
      workflow_name = derive_workflow_name(module_name)
      steps = parse_steps(opts[:steps])
      root_namespace = infer_root_namespace(module_name)

      igniter
      |> generate_workflow_module(module_name, workflow_name, steps, root_namespace)
      |> maybe_generate_test(module_name, workflow_name, opts[:no_test])
    end

    defp derive_workflow_name(module_name) do
      module_name
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end

    defp parse_steps(steps_string) do
      steps_string
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
    end

    defp infer_root_namespace(module_name) do
      module_name
      |> Module.split()
      |> List.first()
    end

    defp generate_workflow_module(igniter, module_name, workflow_name, steps, root_namespace) do
      plan_adds = build_plan_adds(steps, root_namespace)

      contents = """
      defmodule #{inspect(module_name)} do
        use Jido.Tools.ActionPlan,
          name: "#{workflow_name}",
          description: "TODO: Add description",
          schema: []

        alias Jido.Plan

        @impl Jido.Tools.ActionPlan
        def build(_params, context) do
          Plan.new(context: context)
      #{plan_adds}
        end
      end
      """

      Igniter.Project.Module.create_module(igniter, module_name, contents)
    end

    defp build_plan_adds(steps, root_namespace) do
      steps
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {step, index} ->
        action_module = "#{root_namespace}.Actions.#{Macro.camelize(step)}"
        step_atom = String.to_atom(step)

        if index == 0 do
          "    |> Plan.add(:#{step_atom}, #{action_module})"
        else
          prev_step = Enum.at(steps, index - 1)
          "    |> Plan.add(:#{step_atom}, #{action_module}, depends_on: :#{prev_step})"
        end
      end)
    end

    defp maybe_generate_test(igniter, _module_name, _workflow_name, true), do: igniter

    defp maybe_generate_test(igniter, module_name, workflow_name, _no_test) do
      test_module_name = Module.concat(module_name, Test)

      test_contents = """
      defmodule #{inspect(test_module_name)} do
        use ExUnit.Case, async: true

        describe "#{workflow_name}" do
          test "defines a workflow action plan" do
            assert #{inspect(module_name)}.name() == "#{workflow_name}"
            assert function_exported?(#{inspect(module_name)}, :build, 2)
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
  defmodule Mix.Tasks.JidoAction.Gen.Workflow do
    @shortdoc "Requires :igniter dependency"

    @moduledoc """
    #{@shortdoc}

    Add `{:igniter, "~> 0.7", only: [:dev, :test]}` to your deps to use this task.
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.raise("""
      mix jido_action.gen.workflow requires the :igniter dependency.

      Add to your mix.exs:

          {:igniter, "~> 0.7", only: [:dev, :test]}
      """)
    end
  end
end
