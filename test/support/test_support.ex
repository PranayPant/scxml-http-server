defmodule ScxmlHttpEngine.TestSupport do
  @moduledoc """
  Helpers shared by the HTTP engine test suites.
  """

  @fixture [__DIR__, "../fixtures/traffic_light.json"] |> Path.join() |> Path.expand()

  @doc """
  Load the traffic-light AST JSON document as a string (a JSON string of the
  `{"scxml": ...}` AST, as expected by `ScxmlEngine.run/1`).
  """
  @spec document() :: String.t()
  def document do
    File.read!(@fixture)
  end

  @doc """
  Like `document/0` but rewrites the `scxml.id` to a unique value. Use this
  when you register an instance WITHOUT an explicit `instance_id` (so it lands
  under the graph id) and you need to avoid colliding in the unique-key
  registry with other parallel/all tests that share the default fixture id.
  """
  @spec unique_document() :: String.t()
  def unique_document do
    unique_id = "unique_#{System.unique_integer([:positive])}"
    String.replace(document(), "\"test_traffic\"", "\"#{unique_id}\"")
  end

  @doc """
  Generate a unique instance id so parallel tests never collide in the global
  registry.
  """
  @spec unique_id(String.t()) :: String.t()
  def unique_id(prefix) do
    "#{prefix}_#{System.unique_integer([:positive])}"
  end
end
