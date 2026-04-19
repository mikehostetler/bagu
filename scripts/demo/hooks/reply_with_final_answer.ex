defmodule Moto.Scripts.Demo.Hooks.ReplyWithFinalAnswer do
  use Moto.Hook, name: "reply_with_final_answer"

  @impl true
  def call(%Moto.Hooks.BeforeTurn{} = input) do
    {:ok,
     %{
       message: "#{input.message}\n\nReply with only the final answer.",
       metadata: %{reply_style: :final_answer_only}
     }}
  end
end
