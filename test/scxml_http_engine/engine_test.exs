defmodule ScxmlHttpEngine.EngineTest do
  # Not async: these tests mutate the shared global registry + :persistent_term
  # graph store, so serialization avoids cross-test interference.
  use ExUnit.Case, async: false

  alias ScxmlHttpEngine.Engine
  alias ScxmlHttpEngine.TestSupport

  setup do
    instance_id = TestSupport.unique_id("traffic")
    {:ok, instance_id: instance_id}
  end

  describe "register_and_start/2" do
    test "starts an instance and returns its snapshot", %{instance_id: instance_id} do
      assert {:ok, snapshot} = Engine.register_and_start(TestSupport.document(), instance_id)
      assert snapshot.instance_id == instance_id
      assert snapshot.configuration == ["red"]
      assert snapshot.done == false
      assert snapshot.execution_status == :idle
      assert snapshot.active_states == [%{id: "red", status: :running, type: :atomic}]
      assert %{"color" => "red"} in [snapshot.datamodel["data"]]
    end

    test "resolves the instance id from the pid when none is given" do
      # A unique document id avoids colliding in the unique-key registry with
      # tests that share the default "test_traffic" fixture id.
      assert {:ok, snapshot} = Engine.register_and_start(TestSupport.unique_document(), nil)
      assert is_binary(snapshot.instance_id)
      assert snapshot.configuration == ["red"]
    end

    test "returns an error for an invalid document" do
      assert {:error, _reason} = Engine.register_and_start("not json", "bad")
    end
  end

  describe "start_instance/3" do
    test "starts an instance against a previously stored graph", %{instance_id: instance_id} do
      # register_and_start stores the document's graph under its id ("test_traffic").
      {:ok, _} = Engine.register_and_start(TestSupport.document(), instance_id)
      new_id = TestSupport.unique_id("restart")

      assert {:ok, snapshot} = Engine.start_instance("test_traffic", new_id, %{})
      assert snapshot.instance_id == new_id
      assert snapshot.done == false
      assert snapshot.configuration == ["red"]
    end

    test "returns an error for an unknown graph" do
      assert {:error, _reason} = Engine.start_instance("does_not_exist", nil, %{})
    end
  end

  describe "step/3" do
    test "sends an event and returns the settled state", %{instance_id: instance_id} do
      {:ok, %{configuration: ["red"]}} = Engine.register_and_start(TestSupport.document(), instance_id)

      assert {:ok, snapshot} = Engine.step(instance_id, "next", %{})
      assert snapshot.configuration == ["green"]
      assert snapshot.execution_status == :running
      assert snapshot.active_states == [%{id: "green", status: :running, type: :atomic}]
    end

    test "defaults a nil data payload to an empty map", %{instance_id: instance_id} do
      {:ok, _} = Engine.register_and_start(TestSupport.document(), instance_id)

      assert {:ok, %{configuration: ["green"]}} = Engine.step(instance_id, "next", nil)
    end

    test "returns :not_found for an unknown instance" do
      assert {:error, :not_found} = Engine.step("missing_instance", "next", %{})
    end
  end

  describe "snapshot/1" do
    test "returns a snapshot for a running instance", %{instance_id: instance_id} do
      {:ok, _} = Engine.register_and_start(TestSupport.document(), instance_id)

      assert {:ok, snapshot} = Engine.snapshot(instance_id)
      assert snapshot.instance_id == instance_id
      assert snapshot.configuration == ["red"]
    end

    test "returns :not_found for an unknown instance" do
      assert {:error, :not_found} = Engine.snapshot("missing_instance")
    end
  end

  describe "list_instances/0" do
    test "returns snapshots for all running instances", %{instance_id: instance_id} do
      {:ok, _} = Engine.register_and_start(TestSupport.document(), instance_id)

      assert Enum.any?(Engine.list_instances(), &(&1.instance_id == instance_id))
    end

    test "returns a list of snapshots even when none match a specific id", %{instance_id: instance_id} do
      {:ok, _} = Engine.register_and_start(TestSupport.document(), instance_id)

      # The global registry may hold instances from parallel tests, so only
      # assert the shape, not exact contents.
      assert is_list(Engine.list_instances())
    end
  end

  describe "remove_instance/1" do
    test "stops and removes an instance", %{instance_id: instance_id} do
      {:ok, _} = Engine.register_and_start(TestSupport.document(), instance_id)

      assert {:ok, :deleted} = Engine.remove_instance(instance_id)
      assert {:error, :not_found} = Engine.snapshot(instance_id)
    end

    test "returns :not_found for an unknown instance" do
      assert {:error, :not_found} = Engine.remove_instance("missing_instance")
    end
  end
end
