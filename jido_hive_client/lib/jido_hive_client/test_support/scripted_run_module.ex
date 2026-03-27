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

    response = response_for(scenario)
    encoded = Jason.encode!(response)

    case scenario do
      :repairable ->
        repairable_script(context, encoded)

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

  defp response_for(:architect) do
    %{
      "summary" => "architect proposed a shared packet and requested publication",
      "actions" => [
        %{
          "op" => "CLAIM",
          "title" => "Shared packet envelope",
          "body" => "The server should carry a shared turn envelope across clients.",
          "targets" => []
        },
        %{
          "op" => "EVIDENCE",
          "title" => "Tool lineage",
          "body" => "Each turn should forward prompt, tool, and artifact lineage.",
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

  defp response_for(:codex_like), do: response_for(:architect)
  defp response_for(:repairable), do: response_for(:architect)

  defp response_for(:skeptic) do
    %{
      "summary" => "skeptic raised one objection against the shared packet",
      "actions" => [
        %{
          "op" => "OBJECT",
          "title" => "Conflict retention is underspecified",
          "body" => "The shared packet must preserve contradictory tool output explicitly.",
          "severity" => "high",
          "targets" => [%{"entry_ref" => "claim:1"}]
        }
      ],
      "artifacts" => []
    }
  end

  defp response_for(:resolver) do
    %{
      "summary" => "architect resolved the open dispute and marked the room publishable",
      "actions" => [
        %{
          "op" => "REVISE",
          "title" => "Conflict ledger",
          "body" =>
            "Keep a contradiction ledger in the shared envelope and cite it in each turn.",
          "targets" => [%{"dispute_id" => "dispute:1"}]
        },
        %{
          "op" => "DECIDE",
          "title" => "Publishable",
          "body" => "The room is ready for publication after the contradiction ledger revision.",
          "targets" => [%{"dispute_id" => "dispute:1"}]
        }
      ],
      "artifacts" => []
    }
  end

  defp scenario_tool(:architect), do: "context.read"
  defp scenario_tool(:skeptic), do: "critique.scan"
  defp scenario_tool(:resolver), do: "revision.apply"

  defp scripted_opts(context) do
    case Map.get(context, :scenario) do
      nil -> Map.get(context, :driver_opts) || Map.get(context, :run_module_opts) || []
      scenario -> [scenario: scenario]
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
