defmodule JidoHiveClient.TransportHTTPTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.Transport.HTTP

  test "unknown lanes fail closed before transport effects" do
    assert {:error, {:unsupported_lane, :external_runtime_input}} =
             HTTP.get("http://127.0.0.1:9", "/noop",
               lane: :external_runtime_input,
               request_timeout_ms: 1,
               connect_timeout_ms: 1
             )
  end
end
