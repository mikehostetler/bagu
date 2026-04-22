defmodule MotoTest.MemoryAgent do
  use Moto.Agent

  agent do
    id :memory_agent
  end

  defaults do
    model :fast
    instructions "You have conversation memory."
  end

  lifecycle do
    memory do
      mode :conversation
      namespace {:context, :session}
      capture :conversation
      retrieve limit: 4
      inject :instructions
    end
  end
end

defmodule MotoTest.ContextMemoryAgent do
  use Moto.Agent

  agent do
    id :context_memory_agent
  end

  defaults do
    model :fast
    instructions "You have context memory."
  end

  lifecycle do
    memory do
      mode :conversation
      namespace {:context, :session}
      capture :conversation
      retrieve limit: 4
      inject :context
    end
  end
end

defmodule MotoTest.SharedMemoryAgent do
  use Moto.Agent

  agent do
    id :shared_memory_agent
  end

  defaults do
    model :fast
    instructions "You have shared memory."
  end

  lifecycle do
    memory do
      mode :conversation
      namespace :shared
      shared_namespace "shared-demo"
      capture :conversation
      retrieve limit: 4
      inject :context
    end
  end
end

defmodule MotoTest.NoCaptureMemoryAgent do
  use Moto.Agent

  agent do
    id :no_capture_memory_agent
  end

  defaults do
    model :fast
    instructions "You have retrieval only memory."
  end

  lifecycle do
    memory do
      mode :conversation
      namespace {:context, :session}
      capture :off
      retrieve limit: 4
      inject :context
    end
  end
end
