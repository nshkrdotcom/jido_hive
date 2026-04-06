defmodule JidoHiveClient.InterceptorTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.AgentBackends.Mock
  alias JidoHiveClient.{ChatInput, Interceptor}

  test "mock backend extracts deterministic structured objects" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "I think auth is broken because Redis timed out?"
      })

    {:ok, intercepted} = Interceptor.extract(input, backend: Mock)

    assert intercepted.summary == "I think auth is broken because Redis timed out?"

    assert Enum.map(intercepted.context_objects, & &1["object_type"]) == [
             "message",
             "question",
             "hypothesis",
             "evidence",
             "contradiction"
           ]
  end

  test "normalizes intercepted contributions into contribution payloads" do
    contribution =
      Interceptor.to_contribution(
        %{
          chat_text: "We should rollback",
          summary: "We should rollback",
          contribution_type: "chat",
          authority_level: "advisory",
          context_objects: [%{"object_type" => "decision_candidate", "title" => "Rollback"}],
          raw_backend_output: %{"backend" => "mock"}
        },
        %{
          room_id: "room-1",
          participant_id: "alice",
          participant_role: "operator",
          participant_kind: "human"
        }
      )

    assert contribution["room_id"] == "room-1"
    assert contribution["participant_id"] == "alice"

    assert contribution["events"] == [
             %{
               "body" => "We should rollback",
               "event_type" => "chat.message",
               "tags" => []
             }
           ]

    assert contribution["execution"]["backend"] == "mock"
  end
end
