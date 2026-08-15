defmodule ScxmlHttpEngine.TracerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias ScxmlHttpEngine.Tracer

  setup do
    Logger.metadata([])
    Logger.put_process_level(self(), nil)
    :ok
  end

  describe "metadata injection" do
    test "injects request_id from process dictionary into Logger context" do
      Process.put(:request_id, "test-uuid-123")

      _conn = Tracer.call(conn(:get, "/api/v1/engine/run"), [])

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :request_id) == "test-uuid-123"
    end

    test "handles nil request_id gracefully" do
      Process.delete(:request_id)

      _conn = Tracer.call(conn(:get, "/api/v1/engine/run"), [])

      metadata = Logger.metadata()
      assert Keyword.get(metadata, :request_id) == nil
    end
  end

  describe "quiet path suppression" do
    test "sets process level to warning for /healthz" do
      :get
      |> conn("/healthz")
      |> Tracer.call([])
      |> send_resp(200, "ok")

      assert Logger.get_process_level(self()) == :warning
    end

    test "sets process level to warning for /openapi" do
      :get
      |> conn("/openapi")
      |> Tracer.call([])
      |> send_resp(200, "ok")

      assert Logger.get_process_level(self()) == :warning
    end

    test "sets process level to warning for /swaggerui with trailing slash" do
      :get
      |> conn("/swaggerui/")
      |> Tracer.call([])
      |> send_resp(200, "ok")

      assert Logger.get_process_level(self()) == :warning
    end

    test "sets process level to warning for /swaggerui/index.html" do
      :get
      |> conn("/swaggerui/index.html")
      |> Tracer.call([])
      |> send_resp(200, "ok")

      assert Logger.get_process_level(self()) == :warning
    end

    test "does not suppress normal routes" do
      :get
      |> conn("/api/v1/engine/run")
      |> Tracer.call([])
      |> send_resp(200, "ok")

      assert Logger.get_process_level(self()) != :warning
    end
  end

  describe "request completion logging" do
    test "logs info for 2xx responses" do
      log_output =
        capture_log(fn ->
          :get
          |> conn("/api/v1/engine/run")
          |> Tracer.call([])
          |> send_resp(200, "OK")
        end)

      assert log_output =~ "[info]"
      assert log_output =~ "API Request Completed"
    end

    test "logs info for 4xx responses" do
      log_output =
        capture_log(fn ->
          :get
          |> conn("/api/v1/engine/run")
          |> Tracer.call([])
          |> send_resp(404, "Not Found")
        end)

      assert log_output =~ "[info]"
      assert log_output =~ "API Request Completed"
    end

    test "logs error for 5xx responses" do
      log_output =
        capture_log(fn ->
          :post
          |> conn("/api/v1/engine/run")
          |> Tracer.call([])
          |> send_resp(500, "Internal Server Error")
        end)

      assert log_output =~ "[error]"
      assert log_output =~ "API Request Failed"
    end

    test "does not log info for 2xx responses on quiet paths" do
      log_output =
        capture_log(fn ->
          :get
          |> conn("/healthz")
          |> Tracer.call([])
          |> send_resp(200, "ok")
        end)

      refute log_output =~ "API Request Completed"
    end

    test "does log error for 5xx responses even on quiet paths" do
      log_output =
        capture_log(fn ->
          :get
          |> conn("/healthz")
          |> Tracer.call([])
          |> send_resp(500, "fail")
        end)

      assert log_output =~ "[error]"
      assert log_output =~ "API Request Failed"
    end
  end
end
