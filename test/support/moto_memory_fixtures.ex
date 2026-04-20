defmodule MotoTest.MemoryAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You have conversation memory.")
  end

  memory do
    mode(:conversation)
    namespace({:context, :session})
    capture(:conversation)
    retrieve(limit: 4)
    inject(:system_prompt)
  end
end

defmodule MotoTest.ContextMemoryAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You have context memory.")
  end

  memory do
    mode(:conversation)
    namespace({:context, :session})
    capture(:conversation)
    retrieve(limit: 4)
    inject(:context)
  end
end

defmodule MotoTest.SharedMemoryAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You have shared memory.")
  end

  memory do
    mode(:conversation)
    namespace(:shared)
    shared_namespace("shared-demo")
    capture(:conversation)
    retrieve(limit: 4)
    inject(:context)
  end
end

defmodule MotoTest.NoCaptureMemoryAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You have retrieval only memory.")
  end

  memory do
    mode(:conversation)
    namespace({:context, :session})
    capture(:off)
    retrieve(limit: 4)
    inject(:context)
  end
end
