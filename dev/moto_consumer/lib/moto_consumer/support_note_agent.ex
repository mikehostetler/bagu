defmodule MotoConsumer.SupportNoteAgent do
  @moduledoc false

  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can help with secure notes.")
  end

  tools do
    ash_resource(MotoConsumer.Accounts.SecureNote)
  end
end
