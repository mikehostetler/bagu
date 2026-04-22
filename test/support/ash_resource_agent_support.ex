defmodule MotoTest.Support.AshResourceAgent do
  use Moto.Agent

  agent do
    id :ash_resource_agent
  end

  defaults do
    model :fast
    instructions "You can use Ash resource tools."
  end

  capabilities do
    ash_resource MotoTest.Support.User
  end
end
