defmodule JidoHiveClient.ResultDecoderTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.ResultDecoder

  test "extracts fenced json and normalizes the collaboration contract" do
    payload = """
    Here is the result.

    ```json
    {"summary":"ok","actions":[{"op":"CLAIM","title":"A","body":"B","targets":[]}],"artifacts":[]}
    ```
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["summary"] == "ok"
    assert [%{"op" => "CLAIM", "title" => "A", "body" => "B"}] = decoded["actions"]
  end

  test "normalizes codex-style actions when summary is omitted" do
    payload = """
    {"actions":[{"op":"claim","ref":"claim-shared-ledger","body":"Use an append-only log."},{"op":"evidence","body":"It keeps a durable history."}]}
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["summary"] == "collaboration response with actions: CLAIM, EVIDENCE"

    assert [
             %{
               "op" => "CLAIM",
               "title" => "claim-shared-ledger",
               "body" => "Use an append-only log."
             },
             %{"op" => "EVIDENCE", "title" => "EVIDENCE", "body" => "It keeps a durable history."}
           ] = decoded["actions"]
  end
end
