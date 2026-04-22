defmodule Moto.Agent.Dsl.Tool do
  @moduledoc false

  defstruct [:module, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.AshResource do
  @moduledoc false

  defstruct [:resource, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.MCPTools do
  @moduledoc false

  defstruct [:endpoint, :prefix, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.Plugin do
  @moduledoc false

  defstruct [:module, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.SkillRef do
  @moduledoc false

  defstruct [:skill, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.SkillPath do
  @moduledoc false

  defstruct [:path, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.Subagent do
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

defmodule Moto.Agent.Dsl.MemoryMode do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.MemoryNamespace do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.MemorySharedNamespace do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.MemoryCapture do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.MemoryInject do
  @moduledoc false

  defstruct [:value, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.MemoryRetrieve do
  @moduledoc false

  defstruct [:limit, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.BeforeTurnHook do
  @moduledoc false

  defstruct [:hook, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.AfterTurnHook do
  @moduledoc false

  defstruct [:hook, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.InterruptHook do
  @moduledoc false

  defstruct [:hook, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.InputGuardrail do
  @moduledoc false

  defstruct [:guardrail, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.OutputGuardrail do
  @moduledoc false

  defstruct [:guardrail, :__spark_metadata__]
end

defmodule Moto.Agent.Dsl.ToolGuardrail do
  @moduledoc false

  defstruct [:guardrail, :__spark_metadata__]
end
