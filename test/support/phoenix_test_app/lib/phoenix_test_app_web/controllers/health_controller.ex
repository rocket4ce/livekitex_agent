defmodule PhoenixTestAppWeb.HealthController do
  def index(conn, _params) do
    json(conn, %{status: "ok", livekitex_agent: "loaded"})
  end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  defp put_resp_content_type(conn, content_type) do
    put_resp_header(conn, "content-type", content_type)
  end

  defp send_resp(conn, status, body) do
    %{conn | status: status, resp_body: body}
  end

  defp put_resp_header(conn, key, value) do
    headers = [{key, value} | conn.resp_headers]
    %{conn | resp_headers: headers}
  end
end
