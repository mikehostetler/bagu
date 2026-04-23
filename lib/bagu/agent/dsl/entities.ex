defmodule Bagu.Agent.Dsl.Tool do
  @moduledoc false

  defstruct [:module, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.AshResource do
  @moduledoc false

  defstruct [:resource, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.MCPTools do
  @moduledoc false

  defstruct [
    :endpoint,
    :prefix,
    :transport,
    :client_info,
    :protocol_version,
    :capabilities,
    :timeouts,
    :__spark_metadata__
  ]
end

defmodule Bagu.Agent.Dsl.Plugin do
  @moduledoc false

  defstruct [:module, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.SkillRef do
  @moduledoc false

  defstruct [:skill, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.SkillPath do
  @moduledoc false

  defstruct [:path, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.Subagent do
  @moduledoc false

  defstruct [
    :agent,
    :as,
    :description,
    :target,
    :timeout,
    :forward_context,
    :result,
    :__spark_metadata__
  ]
end

defmodule Bagu.Agent.Dsl.Workflow do
  @moduledoc false

  defstruct [
    :workflow,
    :as,
    :description,
    :timeout,
    :forward_context,
    :result,
    :__spark_metadata__
  ]
end

defmodule Bagu.Agent.Dsl.MemoryMode do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.MemoryNamespace do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.MemorySharedNamespace do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.MemoryCapture do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.MemoryInject do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.MemoryRetrieve do
  @moduledoc false

  defstruct [:limit, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.BeforeTurnHook do
  @moduledoc false

  defstruct [:hook, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.AfterTurnHook do
  @moduledoc false

  defstruct [:hook, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.InterruptHook do
  @moduledoc false

  defstruct [:hook, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.InputGuardrail do
  @moduledoc false

  defstruct [:guardrail, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.OutputGuardrail do
  @moduledoc false

  defstruct [:guardrail, :__spark_metadata__]
end

defmodule Bagu.Agent.Dsl.ToolGuardrail do
  @moduledoc false

  defstruct [:guardrail, :__spark_metadata__]
end
