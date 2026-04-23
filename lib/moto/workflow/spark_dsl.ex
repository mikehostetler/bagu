defmodule Moto.Workflow.SparkDsl do
  @moduledoc false

  use Spark.Dsl, default_extensions: [extensions: [Moto.Workflow.Dsl]]
end
