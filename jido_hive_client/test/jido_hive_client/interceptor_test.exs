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

  test "anchors generated objects to the selected context using contextual defaults" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "I think auth is broken because Redis timed out?",
        local_context: %{
          "selected_context_id" => "ctx-root",
          "selected_relation" => "contextual"
        }
      })

    {:ok, intercepted} = Interceptor.extract(input, backend: Mock)

    objects_by_type = Map.new(intercepted.context_objects, &{&1["object_type"], &1})

    assert objects_by_type["question"]["relations"] == [
             %{"relation" => "references", "target_id" => "ctx-root"}
           ]

    assert objects_by_type["hypothesis"]["relations"] == [
             %{"relation" => "derives_from", "target_id" => "ctx-root"}
           ]

    assert objects_by_type["evidence"]["relations"] == [
             %{"relation" => "supports", "target_id" => "ctx-root"}
           ]

    assert objects_by_type["contradiction"]["relations"] == [
             %{"relation" => "contradicts", "target_id" => "ctx-root"}
           ]

    refute Enum.any?(intercepted.context_objects, fn object ->
             Enum.any?(Map.get(object, "relations", []), fn relation ->
               relation["target_id"] in [nil, ""]
             end)
           end)
  end

  test "creates an anchored note when selected context exists but heuristics only produce a message" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "plain status update",
        local_context: %{
          "selected_context_id" => "ctx-root",
          "selected_relation" => "references"
        }
      })

    {:ok, intercepted} = Interceptor.extract(input, backend: Mock)

    assert Enum.map(intercepted.context_objects, & &1["object_type"]) == ["message", "note"]

    assert Enum.find(intercepted.context_objects, &(&1["object_type"] == "note"))["relations"] ==
             [
               %{"relation" => "references", "target_id" => "ctx-root"}
             ]
  end

  test "does not anchor generated objects when selected relation mode is none" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "I think auth is broken because Redis timed out?",
        local_context: %{
          "selected_context_id" => "ctx-root",
          "selected_relation" => "none"
        }
      })

    {:ok, intercepted} = Interceptor.extract(input, backend: Mock)

    refute Enum.any?(intercepted.context_objects, fn object ->
             Map.has_key?(object, "relations")
           end)

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
    assert contribution["kind"] == "chat"

    assert get_in(contribution, ["meta", "events"]) == [
             %{
               "body" => "We should rollback",
               "event_type" => "chat.message",
               "tags" => []
             }
           ]

    assert get_in(contribution, ["meta", "execution", "backend"]) == "mock"
  end

  test "preserves authority level from chat input through interception" do
    {:ok, input} =
      ChatInput.new(%{
        room_id: "room-1",
        participant_id: "alice",
        text: "We should resolve this",
        authority_level: "binding"
      })

    {:ok, intercepted} = Interceptor.extract(input, backend: Mock)
    assert intercepted.authority_level == "binding"
  end
end
