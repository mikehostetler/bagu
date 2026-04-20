defmodule MotoTest.ToolsPluginsTest do
  use MotoTest.Support.Case, async: false

  alias MotoTest.{AddNumbers, MathPlugin, MultiplyNumbers, PluginAgent, ToolAgent}

  test "wraps Jido.Action with Moto.Tool defaults" do
    assert AddNumbers.name() == "add_numbers"
    assert AddNumbers.description() == "Adds two integers together."
    assert %{name: "add_numbers", parameters_schema: %{}} = AddNumbers.to_tool()
  end

  test "exposes configured tool modules and names" do
    assert ToolAgent.tools() == [AddNumbers]
    assert ToolAgent.tool_names() == ["add_numbers"]
  end

  test "wraps Jido.Plugin with Moto.Plugin defaults" do
    assert MathPlugin.name() == "math_plugin"
    assert MathPlugin.state_key() == :math_plugin
    assert MathPlugin.actions() == [MultiplyNumbers]
  end

  test "exposes configured plugin modules and names" do
    assert PluginAgent.plugins() == [MathPlugin]
    assert PluginAgent.plugin_names() == ["math_plugin"]
  end

  test "merges plugin actions into the agent tool registry" do
    assert PluginAgent.tools() == [MultiplyNumbers]
    assert PluginAgent.tool_names() == ["multiply_numbers"]
  end
end
