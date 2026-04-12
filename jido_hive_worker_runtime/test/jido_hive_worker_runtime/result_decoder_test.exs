defmodule JidoHiveWorkerRuntime.ResultDecoderTest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.ResultDecoder

  test "extracts fenced json and normalizes the canonical contribution contract" do
    payload = """
    Here is the result.

    ```json
    {"kind":"reasoning","payload":{"summary":"ok","context_objects":[{"object_type":"belief","title":"A","body":"B","data":{"k":"v"},"scope":{"read":["room"],"write":["author"]},"uncertainty":{"status":"provisional","confidence":0.7},"relations":[]}],"artifacts":[]},"meta":{"status":"completed"}}
    ```
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["kind"] == "reasoning"
    assert get_in(decoded, ["payload", "summary"]) == "ok"
    assert get_in(decoded, ["meta", "status"]) == "completed"

    assert [
             %{
               "object_type" => "belief",
               "title" => "A",
               "body" => "B",
               "data" => %{"k" => "v"}
             }
           ] = get_in(decoded, ["payload", "context_objects"])
  end

  test "defaults the summary when kind is present but summary is omitted" do
    payload = """
    {"kind":"reasoning","payload":{"context_objects":[{"object_type":"note","title":"Shared ledger","body":"Use an append-only log."}],"artifacts":[]}}
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert get_in(decoded, ["payload", "summary"]) == "reasoning contribution"
    assert decoded["meta"] == %{}

    assert [%{"object_type" => "note", "title" => "Shared ledger"}] =
             get_in(decoded, ["payload", "context_objects"])
  end

  test "extracts the first canonical contribution object from surrounding wrapper text" do
    payload = """
    prefix text {"schema_version":"ignored","kind":"decision","payload":{"summary":"Use explicit assignments","context_objects":[{"object_type":"decision","title":"Assignment transport","body":"Use assignment.offer and contribution.submit","relations":[{"relation":"derives_from","target_id":"ctx-1"}]}],"artifacts":[{"artifact_type":"note","title":"operator","body":"Binding decision"}]}} suffix text
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["kind"] == "decision"
    assert get_in(decoded, ["payload", "summary"]) == "Use explicit assignments"

    assert [
             %{
               "object_type" => "decision",
               "title" => "Assignment transport",
               "body" => "Use assignment.offer and contribution.submit",
               "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-1"}]
             }
           ] = get_in(decoded, ["payload", "context_objects"])

    assert [%{"artifact_type" => "note", "title" => "operator"}] =
             get_in(decoded, ["payload", "artifacts"])
  end

  test "rejects the legacy top-level contribution contract" do
    payload = """
    {"summary":"legacy","contribution_type":"reasoning","context_objects":[],"artifacts":[]}
    """

    assert {:error, :invalid_contract} = ResultDecoder.decode(payload)
  end

  test "rejects a wrapper contribution object" do
    payload = """
    {"contribution":{"kind":"reasoning","payload":{"summary":"wrapped","context_objects":[],"artifacts":[]}}}
    """

    assert {:error, :invalid_contract} = ResultDecoder.decode(payload)
  end
end
