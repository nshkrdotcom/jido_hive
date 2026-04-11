defmodule JidoHiveWorkerRuntime.TestSupport.ScriptedRunModule do
  @moduledoc false

  alias ASM.Event
  alias CliSubprocessCore.Payload

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :run_id, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> then(fn context -> Task.start_link(fn -> emit(context) end) end)
  end

  @spec start(map()) :: {:ok, pid()}
  def start(%{} = context) do
    {:ok, spawn(fn -> emit(context) end)}
  end

  defp emit(context) do
    maybe_delay(context)

    notify_subscriber(
      context,
      :run_started,
      Payload.RunStarted.new(command: "jido-hive-scripted")
    )

    Enum.each(script(context), fn {kind, payload} ->
      notify_subscriber(context, kind, payload)
    end)

    if is_pid(context.subscriber) do
      send(context.subscriber, {:asm_run_done, context.run_id})
    end
  end

  defp script(context) do
    scenario =
      context
      |> scripted_opts()
      |> Keyword.get(:scenario, :analyst)

    response = response_for(scenario, context)
    encoded = Jason.encode!(response)

    case scenario do
      :repairable ->
        repairable_script(context, encoded)

      :unrepairable ->
        unrepairable_script(context)

      :codex_like ->
        [
          {:raw,
           %{
             "content" => %{
               "type" => "item.started",
               "item" => %{
                 "id" => "item_1",
                 "type" => "command_execution",
                 "command" => "/bin/bash -lc pwd",
                 "status" => "in_progress",
                 "aggregated_output" => "",
                 "exit_code" => nil
               }
             },
             "metadata" => %{},
             "stream" => "stdout"
           }},
          {:raw,
           %{
             "content" => %{
               "type" => "item.completed",
               "item" => %{
                 "id" => "item_1",
                 "type" => "command_execution",
                 "command" => "/bin/bash -lc pwd",
                 "status" => "completed",
                 "aggregated_output" => "/tmp/jido-hive-client-test\n",
                 "exit_code" => 0
               }
             },
             "metadata" => %{},
             "stream" => "stdout"
           }},
          {:assistant_message,
           %{
             "role" => "assistant",
             "content" => [encoded],
             "metadata" => %{},
             "model" => "gpt-5.4"
           }},
          {:result,
           %{
             "status" => "completed",
             "stop_reason" => "end_turn",
             "output" => %{"usage" => %{"input_tokens" => 10, "output_tokens" => 20}},
             "metadata" => %{}
           }}
        ]

      _other ->
        [
          {:tool_call,
           %{
             "event_type" => "tool_call",
             "tool_name" => scenario_tool(scenario),
             "status" => "ok",
             "input" => %{"scope" => "shared_room"},
             "output" => %{"scenario" => Atom.to_string(scenario)}
           }},
          {:assistant_delta, Payload.AssistantDelta.new(content: encoded)},
          {:result, Payload.Result.new(status: :completed, stop_reason: "end_turn")}
        ]
    end
  end

  defp repairable_script(context, encoded) do
    if String.ends_with?(to_string(context.run_id), "-repair") do
      [
        {:assistant_message,
         %{
           "role" => "assistant",
           "content" => [encoded],
           "metadata" => %{},
           "model" => "gpt-5.4"
         }},
        {:result,
         %{
           "status" => "completed",
           "stop_reason" => "end_turn",
           "output" => %{"usage" => %{"input_tokens" => 5, "output_tokens" => 10}},
           "metadata" => %{}
         }}
      ]
    else
      [
        {:assistant_message,
         %{
           "role" => "assistant",
           "content" => [
             "analysis pass found two substrate insights and one note, but this is not JSON"
           ],
           "metadata" => %{},
           "model" => "gpt-5.4"
         }},
        {:result,
         %{
           "status" => "completed",
           "stop_reason" => "end_turn",
           "output" => %{"usage" => %{"input_tokens" => 5, "output_tokens" => 10}},
           "metadata" => %{}
         }}
      ]
    end
  end

  defp unrepairable_script(context) do
    content =
      if String.ends_with?(to_string(context.run_id), "-repair") do
        "analysis pass still not returning valid contribution json"
      else
        "I found some useful ideas but I am not returning JSON"
      end

    [
      {:assistant_message,
       %{
         "role" => "assistant",
         "content" => [content],
         "metadata" => %{},
         "model" => "gpt-5.4"
       }},
      {:result,
       %{
         "status" => "completed",
         "stop_reason" => "end_turn",
         "output" => %{"usage" => %{"input_tokens" => 5, "output_tokens" => 10}},
         "metadata" => %{}
       }}
    ]
  end

  defp response_for(:analyst, context) do
    participant_id = prompt_value(context, "participant_id") || "worker"

    %{
      "summary" => "analysis pass added substrate beliefs and notes from #{participant_id}",
      "contribution_type" => "reasoning",
      "authority_level" => "advisory",
      "context_objects" => [
        %{
          "object_type" => "belief",
          "title" => "Server-owned room state",
          "body" => "The server should own room state and dispatch explicit assignments.",
          "data" => %{},
          "scope" => %{"read" => ["room"], "write" => ["author"]},
          "uncertainty" => %{"status" => "provisional", "confidence" => 0.8},
          "relations" => []
        },
        %{
          "object_type" => "note",
          "title" => "Filtered context views",
          "body" => "Assignments should include filtered context instead of a mutable packet.",
          "data" => %{},
          "scope" => %{"read" => ["room"], "write" => ["author"]},
          "uncertainty" => %{"status" => "provisional", "confidence" => 0.7},
          "relations" => []
        }
      ],
      "artifacts" => []
    }
  end

  defp response_for(:architect, context), do: response_for(:analyst, context)
  defp response_for(:codex_like, context), do: response_for(:analyst, context)
  defp response_for(:repairable, context), do: response_for(:analyst, context)
  defp response_for(:unrepairable, context), do: response_for(:analyst, context)

  defp response_for(:skeptic, _context) do
    %{
      "summary" => "critique pass added one open question",
      "contribution_type" => "reasoning",
      "authority_level" => "advisory",
      "context_objects" => [
        %{
          "object_type" => "question",
          "title" => "Human approval path",
          "body" => "The binding human approval path still needs a crisp contract.",
          "data" => %{},
          "scope" => %{"read" => ["room"], "write" => ["author"]},
          "uncertainty" => %{"status" => "provisional", "confidence" => 0.9},
          "relations" => []
        }
      ],
      "artifacts" => []
    }
  end

  defp response_for(:resolver, _context) do
    %{
      "summary" => "resolution pass added one decision",
      "contribution_type" => "decision",
      "authority_level" => "advisory",
      "context_objects" => [
        %{
          "object_type" => "decision",
          "title" => "Room timeline as system of record",
          "body" => "The room timeline should be the canonical UI-facing audit trail.",
          "data" => %{},
          "scope" => %{"read" => ["room"], "write" => ["author"]},
          "uncertainty" => %{"status" => "provisional", "confidence" => 0.85},
          "relations" => []
        }
      ],
      "artifacts" => []
    }
  end

  defp scenario_tool(:analyst), do: "context.read"
  defp scenario_tool(:architect), do: "context.read"
  defp scenario_tool(:skeptic), do: "critique.scan"
  defp scenario_tool(:resolver), do: "revision.apply"

  defp prompt_value(context, key) do
    with prompt when is_binary(prompt) <- Map.get(context, :prompt),
         {:ok, payload} <- decode_packet(prompt) do
      Map.get(payload, key)
    else
      _other -> nil
    end
  end

  defp decode_packet(prompt) when is_binary(prompt) do
    case Regex.run(~r/Assignment packet JSON:\s*(\{.*\})\s*\z/s, prompt, capture: :all_but_first) do
      [json] -> Jason.decode(json)
      _other -> {:error, :packet_not_found}
    end
  end

  defp scripted_opts(context) do
    case Map.get(context, :scenario) do
      nil -> Map.get(context, :driver_opts) || Map.get(context, :run_module_opts) || []
      scenario -> [scenario: scenario]
    end
  end

  defp maybe_delay(context) do
    delay_ms =
      context
      |> scripted_opts()
      |> Keyword.get(:delay_ms, 0)

    if is_integer(delay_ms) and delay_ms > 0 do
      Process.sleep(delay_ms)
    end
  end

  defp notify_subscriber(context, kind, payload) when is_pid(context.subscriber) do
    event = %Event{
      id: Event.generate_id(),
      kind: kind,
      run_id: context.run_id,
      session_id: context.session_id,
      provider: context.provider,
      payload: payload,
      timestamp: DateTime.utc_now()
    }

    send(context.subscriber, {:asm_run_event, context.run_id, event})
  end

  defp notify_subscriber(_context, _kind, _payload), do: :ok
end
