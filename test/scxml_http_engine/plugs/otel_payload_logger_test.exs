defmodule ScxmlHttpEngine.Plugs.OtelPayloadLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias ScxmlHttpEngine.Plugs.OtelPayloadLogger

  # Run the request part of the logger plug (builds the conn, logs the request,
  # and caches the body). Invoked inside `with_level` to capture the log output.
  defp run_plug(method, path, req_body, headers) do
    conn =
      method
      |> conn(path, req_body)
      |> put_req_header("content-type", "application/json")

    conn =
      Enum.reduce(headers, conn, fn {name, val}, acc -> put_req_header(acc, name, val) end)

    OtelPayloadLogger.call(conn, [])
  end

  # Temporarily set the Logger level, run `fun` capturing logs, then restore.
  defp with_level(level, fun) do
    old = Logger.level()

    try do
      Logger.configure(level: level)
      capture_log(fun)
    after
      Logger.configure(level: old)
    end
  end

  describe "body caching" do
    test "reads the request body once and caches it in conn.assigns" do
      conn = run_plug(:post, "/statecharts", ~s({"document":"x"}), [])

      assert conn.assigns[:raw_request_body] == ~s({"document":"x"})
    end
  end

  describe "debug level (full fidelity)" do
    test "logs full headers and body on the request" do
      log =
        with_level(:debug, fn ->
          run_plug(:post, "/statecharts", ~s({"a":1}), [{"authorization", "Bearer secret"}, {"cookie", "sid=abc"}])
        end)

      assert log =~ "▶ REQUEST POST /statecharts"
      assert log =~ ~s({"a":1})
      # Debug keeps sensitive headers.
      assert log =~ "Bearer secret"
      assert log =~ "sid=abc"
    end

    test "logs full response body and headers via before_send" do
      log =
        with_level(:debug, fn ->
          :post
          |> run_plug("/statecharts", ~s({"a":1}), [])
          |> send_resp(200, ~s({"ok":true}))
        end)

      assert log =~ "◀ RESPONSE 200"
      assert log =~ ~s({"ok":true})
    end
  end

  describe "info level (scrubbed + truncated)" do
    test "strips sensitive headers from the log" do
      log =
        with_level(:info, fn ->
          run_plug(:post, "/statecharts", ~s({"a":1}), [{"authorization", "Bearer secret"}, {"cookie", "sid=abc"}])
        end)

      assert log =~ "▶ REQUEST POST /statecharts"
      refute log =~ "Bearer secret"
      refute log =~ "sid=abc"
    end

    test "keeps bodies under the 4096-byte truncation limit" do
      body = ~s({"a":1})
      log = with_level(:info, fn -> run_plug(:post, "/statecharts", body, []) end)

      assert log =~ body
    end

    test "truncates bodies longer than 4096 bytes" do
      long_body = String.duplicate("a", 4096) <> "UNIQUE_TAIL"
      log = with_level(:info, fn -> run_plug(:post, "/statecharts", long_body, []) end)

      # The first 4096 chars are kept...
      assert log =~ String.duplicate("a", 4096)
      # ...but the unique tail beyond the cutoff is dropped.
      refute log =~ "UNIQUE_TAIL"
      # Sanity: the full body is longer than the 4096-byte cutoff.
      assert byte_size(long_body) > 4096
    end

    test "logs a scrubbed, non-sensitive response via before_send" do
      log =
        with_level(:info, fn ->
          :post
          |> run_plug("/statecharts", ~s({"a":1}), [])
          |> send_resp(200, ~s({"secret":"value"}))
        end)

      assert log =~ "◀ RESPONSE 200"
      # INFO keeps the (short) response body but no headers are dumped.
      assert log =~ "secret"
    end
  end
end
