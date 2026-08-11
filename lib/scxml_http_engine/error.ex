defmodule ScxmlHttpEngine.Error do
  @moduledoc """
  Maps `Engine` result tuples to HTTP status codes and JSON error bodies, so
  route handlers stay declarative.
  """

  @ok 200
  @bad_request 400
  @not_found 404

  @doc """
  Map an `Engine` return to a `{status, body}` pair, where `body` is already a
  JSON-encoded map.

  Used for actions that produce resource state (events, snapshots, creation).
  """
  @spec to_json(term()) :: {non_neg_integer(), String.t()}
  def to_json({:ok, snapshot}) when is_map(snapshot), do: {@ok, Jason.encode!(snapshot)}

  def to_json({:ok, :deleted}), do: {@ok, Jason.encode!(%{deleted: true})}

  def to_json({:ok, snapshots}) when is_list(snapshots), do: {@ok, Jason.encode!(snapshots)}

  def to_json({:error, :not_found}), do: {@not_found, error_body("instance not found")}

  def to_json({:error, reason}), do: {@bad_request, error_body(inspect(reason))}

  @doc """
  Build a JSON error body for a message.
  """
  @spec error_body(String.t()) :: String.t()
  def error_body(message), do: Jason.encode!(%{error: message})
end
