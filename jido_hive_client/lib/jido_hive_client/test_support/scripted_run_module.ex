defmodule JidoHiveClient.TestSupport.ScriptedRunModule do
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
      |> Keyword.get(:scenario, :architect)

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
             "Submitted a claim, evidence, and publish recommendation for the shared packet."
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
        "Architect summary: claim shared packet, evidence tool lineage, publish after review."
      else
        "I propose a shared packet with a claim, supporting evidence, and a publish request."
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

  defp response_for(:architect, context) do
    participant_id = prompt_value(context, ["turn", "participant_id"]) || "worker"

    %{
      "summary" => "proposal pass added claim and evidence from #{participant_id}",
      "actions" => [
        %{
          "op" => "CLAIM",
          "title" => "Shared packet envelope #{participant_id}",
          "body" =>
            "The server should carry a shared turn envelope across clients and keep the distributed turn budget explicit.",
          "targets" => []
        },
        %{
          "op" => "EVIDENCE",
          "title" => "Tool lineage #{participant_id}",
          "body" =>
            "Each turn should forward prompt, tool, and artifact lineage so later workers can continue the shared build-up.",
          "targets" => []
        },
        %{
          "op" => "PUBLISH",
          "title" => "Publish after review",
          "body" => "Prepare GitHub and Notion publication payloads from the final room.",
          "targets" => []
        }
      ],
      "artifacts" => []
    }
  end

  defp response_for(:codex_like, context), do: response_for(:architect, context)
  defp response_for(:repairable, context), do: response_for(:architect, context)
  defp response_for(:unrepairable, context), do: response_for(:architect, context)

  defp response_for(:skeptic, context) do
    participant_id = prompt_value(context, ["turn", "participant_id"]) || "worker"
    target_entry_ref = first_entry_ref(context) || "claim:1"

    %{
      "summary" => "critique pass opened one objection from #{participant_id}",
      "actions" => [
        %{
          "op" => "OBJECT",
          "title" => "Conflict retention needs more structure",
          "body" =>
            "The shared packet should preserve contradictory tool output and distributed turn ownership explicitly.",
          "severity" => "high",
          "targets" => [%{"entry_ref" => target_entry_ref}]
        }
      ],
      "artifacts" => []
    }
  end

  defp response_for(:resolver, context) do
    dispute_id = first_open_dispute_id(context) || "dispute:1"

    %{
      "summary" => "resolution pass resolved #{dispute_id}",
      "actions" => [
        %{
          "op" => "REVISE",
          "title" => "Conflict ledger",
          "body" =>
            "Keep a contradiction ledger in the shared envelope and cite it in each turn.",
          "targets" => [%{"dispute_id" => dispute_id}]
        },
        %{
          "op" => "DECIDE",
          "title" => "Publishable",
          "body" => "The room is ready for publication after the contradiction ledger revision.",
          "targets" => [%{"dispute_id" => dispute_id}]
        }
      ],
      "artifacts" => []
    }
  end

  defp scenario_tool(:architect), do: "context.read"
  defp scenario_tool(:skeptic), do: "critique.scan"
  defp scenario_tool(:resolver), do: "revision.apply"

  defp first_open_dispute_id(context) do
    prompt_values(context, ["referee", "open_disputes"])
    |> List.wrap()
    |> Enum.find_value(fn dispute ->
      Map.get(dispute, "dispute_id") || Map.get(dispute, :dispute_id)
    end)
  end

  defp first_entry_ref(context) do
    prompt_values(context, ["shared", "entries"])
    |> List.wrap()
    |> Enum.find_value(fn entry ->
      case Map.get(entry, "entry_type") || Map.get(entry, :entry_type) do
        "claim" ->
          Map.get(entry, "entry_ref") || Map.get(entry, :entry_ref)

        _other ->
          nil
      end
    end)
  end

  defp prompt_value(context, path) do
    context
    |> prompt_values(path)
    |> case do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp prompt_values(context, path) when is_list(path) do
    with prompt when is_binary(prompt) <- Map.get(context, :prompt),
         {:ok, envelope} <- decode_envelope(prompt) do
      get_in(envelope, Enum.map(path, &to_string/1))
    else
      _other -> nil
    end
  end

  defp decode_envelope(prompt) when is_binary(prompt) do
    case Regex.run(~r/Shared envelope JSON:\s*(\{.*\})\s*\z/s, prompt, capture: :all_but_first) do
      [json] -> Jason.decode(json)
      _other -> {:error, :envelope_not_found}
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
