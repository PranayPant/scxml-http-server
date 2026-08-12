defmodule ScxmlHttpEngine.RouterTest do
  # Not async: these request real statechart instances through the shared
  # global registry, so serializing keeps the registry state predictable.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ScxmlHttpEngine.Router
  alias ScxmlHttpEngine.TestSupport

  setup do
    instance_id = TestSupport.unique_id("router")
    {:ok, instance_id: instance_id}
  end

  defp call(method, path, body) do
    conn =
      method
      |> conn(path, body)
      |> put_req_header("content-type", "application/json")

    Router.call(conn, [])
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  describe "GET /healthz" do
    test "returns 200 ok" do
      conn = :get |> conn("/healthz") |> Router.call([])
      assert conn.status == 200
      assert conn.resp_body == "ok"
    end
  end

  describe "POST /statecharts" do
    test "registers and starts an instance, returning 201", %{instance_id: instance_id} do
      body = Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id})
      conn = call(:post, "/statecharts", body)

      assert conn.status == 201
      assert %{"instance_id" => ^instance_id, "configuration" => ["red"]} = json_body(conn)
    end

    test "returns 400 for a malformed JSON body" do
      conn = call(:post, "/statecharts", "not json at all")
      assert conn.status == 400
      assert %{"error" => _} = json_body(conn)
    end

    test "returns 400 when the document field is missing" do
      conn = call(:post, "/statecharts", Jason.encode!(%{}))
      assert conn.status == 400
      assert %{"error" => "invalid request body"} = json_body(conn)
    end

    test "returns 400 when the document is not a valid parseable AST" do
      body = Jason.encode!(%{document: Jason.encode!(%{scxml: "garbage"})})
      conn = call(:post, "/statecharts", body)

      # The `document` field parses (so we reach Engine), but the library
      # rejects the AST, mapping to the `to_created` error fallback.
      assert conn.status == 400
      assert %{"error" => _reason} = json_body(conn)
    end
  end

  describe "POST /instances" do
    test "starts an instance from a stored graph, returning 201" do
      # Store the graph first. Use a unique instance_id so the store call does
      # not register under the shared "test_traffic" registry key; the graph is
      # stored under the document id ("test_traffic") regardless.
      store_id = TestSupport.unique_id("store")
      _store = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: store_id}))

      new_id = TestSupport.unique_id("start")
      body = Jason.encode!(%{graph_id: "test_traffic", instance_id: new_id})
      conn = call(:post, "/instances", body)

      assert conn.status == 201
      assert %{"instance_id" => ^new_id, "configuration" => ["red"]} = json_body(conn)
    end

    test "returns 400 for a malformed JSON body" do
      conn = call(:post, "/instances", "not json")
      assert conn.status == 400
    end

    test "returns 400 when graph_id is missing" do
      conn = call(:post, "/instances", Jason.encode!(%{}))
      assert conn.status == 400
      assert json_body(conn) == %{"error" => "invalid request body"}
    end
  end

  describe "GET /instances/:id" do
    test "returns a snapshot for a running instance", %{instance_id: instance_id} do
      _ = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id}))

      conn = call(:get, "/instances/#{instance_id}", "")
      assert conn.status == 200
      assert %{"instance_id" => ^instance_id, "configuration" => ["red"]} = json_body(conn)
    end

    test "returns 404 for an unknown instance" do
      conn = call(:get, "/instances/missing", "")
      assert conn.status == 404
    end
  end

  describe "POST /instances/:id/events" do
    test "sends an event and returns the settled state, 200", %{instance_id: instance_id} do
      _ = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id}))

      conn = call(:post, "/instances/#{instance_id}/events", Jason.encode!(%{name: "next", data: %{}}))
      assert conn.status == 200
      assert %{"configuration" => ["green"]} = json_body(conn)
    end

    test "returns 400 for a malformed JSON body", %{instance_id: instance_id} do
      _ = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id}))

      conn = call(:post, "/instances/#{instance_id}/events", "not json")
      assert conn.status == 400
    end

    test "returns 400 when name is missing", %{instance_id: instance_id} do
      _ = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id}))

      conn = call(:post, "/instances/#{instance_id}/events", Jason.encode!(%{}))
      assert conn.status == 400
      assert json_body(conn) == %{"error" => "invalid request body"}
    end
  end

  describe "DELETE /instances/:id" do
    test "stops an instance, returning a deleted payload", %{instance_id: instance_id} do
      _ = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id}))

      conn = call(:delete, "/instances/#{instance_id}", "")
      assert conn.status == 200
      assert json_body(conn) == %{"deleted" => true}

      # Now it is gone.
      assert call(:get, "/instances/#{instance_id}", "").status == 404
    end

    test "returns 404 for an unknown instance" do
      conn = call(:delete, "/instances/missing", "")
      assert conn.status == 404
    end
  end

  describe "GET /instances" do
    test "lists running instances", %{instance_id: instance_id} do
      _ = call(:post, "/statecharts", Jason.encode!(%{document: TestSupport.document(), instance_id: instance_id}))

      conn = call(:get, "/instances", "")
      assert conn.status == 200
      assert Enum.any?(json_body(conn), &(&1["instance_id"] == instance_id))
    end
  end

  describe "unknown route" do
    test "returns 404" do
      conn = call(:get, "/nope", "")
      assert conn.status == 404
    end
  end
end
