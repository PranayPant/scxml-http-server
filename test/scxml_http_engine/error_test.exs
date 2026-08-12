defmodule ScxmlHttpEngine.ErrorTest do
  use ExUnit.Case, async: true

  alias ScxmlHttpEngine.Error

  describe "to_json/1" do
    test "maps a {:ok, map} snapshot to a 200 JSON response" do
      snapshot = %{instance_id: "x", configuration: ["on"], datamodel: %{}, done: false}
      {status, body} = Error.to_json({:ok, snapshot})
      assert status == 200

      assert Jason.decode!(body) == %{
               "instance_id" => "x",
               "configuration" => ["on"],
               "datamodel" => %{},
               "done" => false
             }
    end

    test "maps a {:ok, :deleted} to a 200 JSON response" do
      {status, body} = Error.to_json({:ok, :deleted})
      assert status == 200
      assert Jason.decode!(body) == %{"deleted" => true}
    end

    test "maps a {:ok, list} of snapshots to a 200 JSON array" do
      snapshots = [%{instance_id: "a"}, %{instance_id: "b"}]
      {status, body} = Error.to_json({:ok, snapshots})
      assert status == 200
      assert Jason.decode!(body) == [%{"instance_id" => "a"}, %{"instance_id" => "b"}]
    end

    test "maps {:error, :not_found} to a 404 JSON body" do
      {status, body} = Error.to_json({:error, :not_found})
      assert status == 404
      assert Jason.decode!(body) == %{"error" => "instance not found"}
    end

    test "maps any other {:error, reason} to a 400 JSON body" do
      {status, body} = Error.to_json({:error, {:graph_not_found, "g"}})
      assert status == 400
      assert Jason.decode!(body) == %{"error" => inspect({:graph_not_found, "g"})}
    end
  end

  describe "error_body/1" do
    test "builds a JSON error object from a message" do
      assert Jason.decode!(Error.error_body("boom")) == %{"error" => "boom"}
    end
  end
end
