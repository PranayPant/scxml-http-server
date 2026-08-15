defmodule ScxmlHttpEngine.Handlers.Healthz do
  @moduledoc """
  Handler for `GET /healthz` — liveness probe.
  """

  @behaviour Plug

  alias OpenApiSpex.Operation

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Plug.Conn.send_resp(conn, 200, "ok")
  end

  @doc false
  def open_api_operation(_opts) do
    %Operation{
      operationId: "HealthzController.index",
      summary: "Liveness probe",
      description: "Returns 200 OK when the service is alive.",
      tags: ["System"],
      responses: %{
        200 => Operation.response("OK", "text/plain", %OpenApiSpex.Schema{type: :string})
      }
    }
  end
end
