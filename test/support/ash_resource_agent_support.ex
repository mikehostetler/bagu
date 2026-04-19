defmodule MotoTest.Support.AshResourceAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can use Ash resource tools.")
  end

  tools do
    ash_resource(MotoTest.Support.User)
  end
end
