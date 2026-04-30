defmodule Jidoka.Runtime do
  @moduledoc """
  Default Jido runtime instance for Jidoka agents.

  Generated Jidoka agents use this shared runtime when you call their
  `start_link/1` helper or `Jidoka.start_agent/2`.

  If your application needs an OTP instance scoped runtime, define your own Jido
  instance in the host app and start the generated Jidoka runtime module there:

      defmodule MyApp.AgentRuntime do
        use Jido, otp_app: :my_app
      end

      # in your application supervision tree
      children = [MyApp.AgentRuntime]

      {:ok, pid} =
        MyApp.AgentRuntime.start_agent(
          MyApp.SupportAgent.runtime_module(),
          id: "support-router"
        )

      {:ok, reply} = Jidoka.chat(pid, "Triage this ticket.")

  This keeps Jidoka as the authoring onramp while letting advanced applications
  use Jido's instance-level registry, task supervisor, agent supervisor,
  scheduler, debug configuration, worker pools, partitions, and persistence
  primitives directly.
  """

  use Jido, otp_app: :jidoka
end
