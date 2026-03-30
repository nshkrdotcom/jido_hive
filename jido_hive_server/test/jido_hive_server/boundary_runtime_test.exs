defmodule JidoHiveServer.BoundaryRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.TargetDescriptor
  alias JidoHiveServer.BoundaryRuntime
  alias JidoHiveServer.TestSupport.BoundaryTestAdapter

  test "prepares a boundary-backed session and stores reopen metadata for later turns" do
    store = start_supervised!(BoundaryTestAdapter)
    target = boundary_target()
    descriptor = boundary_target_descriptor()

    assert {:ok, prepared} =
             BoundaryRuntime.prepare_session(
               target,
               %{},
               target_descriptor: descriptor,
               adapter: BoundaryTestAdapter,
               adapter_opts: [store: store],
               room_id: "room-boundary-1",
               job_id: "job-boundary-1",
               participant_id: "worker-01"
             )

    assert prepared.session["execution_surface"]["surface_kind"] == "guest_bridge"
    assert prepared.session["boundary"]["descriptor"]["descriptor_version"] == 1

    assert prepared.session["boundary"]["descriptor"]["boundary_session_id"] ==
             "bnd-hive-room-1"

    assert prepared.boundary_sessions["target-boundary-1"]["boundary_session_id"] ==
             "bnd-hive-room-1"

    assert prepared.boundary_sessions["target-boundary-1"]["reopen_request"]["boundary_session_id"] ==
             "bnd-hive-room-1"

    assert BoundaryTestAdapter.calls(store) == [
             {:allocate, "bnd-hive-room-1"},
             {:claim, "bnd-hive-room-1"}
           ]
  end

  test "reopens a retained boundary_session_id instead of allocating a fresh boundary every turn" do
    store = start_supervised!(BoundaryTestAdapter)
    target = boundary_target()
    descriptor = boundary_target_descriptor()

    assert {:ok, first} =
             BoundaryRuntime.prepare_session(
               target,
               %{},
               target_descriptor: descriptor,
               adapter: BoundaryTestAdapter,
               adapter_opts: [store: store],
               room_id: "room-boundary-2",
               job_id: "job-boundary-1",
               participant_id: "worker-01"
             )

    assert {:ok, second} =
             BoundaryRuntime.prepare_session(
               target,
               first.boundary_sessions,
               target_descriptor: descriptor,
               adapter: BoundaryTestAdapter,
               adapter_opts: [store: store],
               room_id: "room-boundary-2",
               job_id: "job-boundary-2",
               participant_id: "worker-01"
             )

    assert second.session["boundary"]["descriptor"]["boundary_session_id"] == "bnd-hive-room-1"

    assert second.boundary_sessions["target-boundary-1"]["boundary_session_id"] ==
             "bnd-hive-room-1"

    assert BoundaryTestAdapter.calls(store) == [
             {:allocate, "bnd-hive-room-1"},
             {:claim, "bnd-hive-room-1"},
             {:reopen, "bnd-hive-room-1"},
             {:claim, "bnd-hive-room-1"}
           ]
  end

  test "fails closed when a retained or allocated boundary descriptor uses an unsupported version" do
    store = start_supervised!(BoundaryTestAdapter)
    descriptor = boundary_target_descriptor()

    BoundaryTestAdapter.put_descriptor(store, "bnd-hive-unsupported", %{
      descriptor_version: 2,
      boundary_session_id: "bnd-hive-unsupported",
      backend_kind: :microvm,
      boundary_class: :leased_cell,
      status: :ready,
      attach_ready?: true,
      workspace: %{
        workspace_root: "/srv/hive",
        snapshot_ref: nil,
        artifact_namespace: "req-hive-unsupported"
      },
      attach: %{
        mode: :attachable,
        execution_surface: %{
          surface_kind: :guest_bridge,
          transport_options: %{"destination" => "boundary.example"},
          target_id: "target-boundary-unsupported",
          lease_ref: "lease-boundary-unsupported",
          surface_ref: "surface-boundary-unsupported",
          boundary_class: :leased_cell,
          observability: %{}
        },
        working_directory: "/srv/hive"
      },
      checkpointing: %{supported?: false, last_checkpoint_id: nil},
      policy_intent_echo: %{},
      refs: %{
        target_id: "target-boundary-unsupported",
        runtime_ref: "runtime-boundary-unsupported",
        correlation_id: "corr-boundary-unsupported",
        request_id: "req-boundary-unsupported"
      },
      extensions: %{},
      metadata: %{}
    })

    assert {:error, error} =
             BoundaryRuntime.prepare_session(
               Map.put(boundary_target(), :boundary_request, %{
                 boundary_session_id: "bnd-hive-unsupported",
                 backend_kind: :microvm,
                 boundary_class: :leased_cell,
                 attach: %{mode: :attachable, working_directory: "/srv/hive"},
                 policy_intent: %{sandbox_level: :strict},
                 refs: %{
                   target_id: "target-boundary-unsupported",
                   runtime_ref: "runtime-boundary-unsupported",
                   correlation_id: "corr-boundary-unsupported",
                   request_id: "req-boundary-unsupported"
                 },
                 allocation_ttl_ms: 250
               }),
               %{},
               target_descriptor: descriptor,
               adapter: BoundaryTestAdapter,
               adapter_opts: [store: store],
               room_id: "room-boundary-unsupported",
               job_id: "job-boundary-unsupported",
               participant_id: "worker-01"
             )

    assert Exception.message(error) =~ "descriptor_version"
  end

  test "keeps authoritative execution policy stricter than the descriptor echo" do
    store = start_supervised!(BoundaryTestAdapter)
    descriptor = boundary_target_descriptor()

    target =
      boundary_target()
      |> Map.put(:execution_environment, %{
        "workspace_root" => "/srv/hive",
        "allowed_tools" => [],
        "approval_posture" => "manual",
        "permission_mode" => "default"
      })
      |> Map.put(:boundary_request, %{
        boundary_session_id: "bnd-hive-denied-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/srv/hive"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :none,
          allowed_tools: ["git.push"],
          file_scope: "/srv/hive"
        },
        refs: %{
          target_id: "target-boundary-1",
          lease_ref: "lease-boundary-1",
          surface_ref: "surface-boundary-1",
          runtime_ref: "runtime-boundary-1",
          correlation_id: "corr-boundary-denied-1",
          request_id: "req-boundary-denied-1"
        },
        allocation_ttl_ms: 250
      })

    assert {:ok, prepared} =
             BoundaryRuntime.prepare_session(
               target,
               %{},
               target_descriptor: descriptor,
               adapter: BoundaryTestAdapter,
               adapter_opts: [store: store],
               room_id: "room-boundary-denied-1",
               job_id: "job-boundary-denied-1",
               participant_id: "worker-01"
             )

    assert prepared.session["execution_environment"]["allowed_tools"] == []
    assert prepared.session["execution_environment"]["approval_posture"] == "manual"
    assert prepared.session["execution_environment"]["permission_mode"] == "default"
  end

  test "fails closed when Hive is handed a non-attachable boundary" do
    store = start_supervised!(BoundaryTestAdapter)
    descriptor = boundary_target_descriptor()

    assert {:error, error} =
             BoundaryRuntime.prepare_session(
               Map.put(boundary_target(), :boundary_request, %{
                 boundary_session_id: "bnd-hive-non-attachable",
                 backend_kind: :microvm,
                 boundary_class: :leased_cell,
                 attach: %{mode: :not_applicable, working_directory: "/srv/hive"},
                 policy_intent: %{sandbox_level: :strict},
                 refs: %{
                   target_id: "target-boundary-1",
                   runtime_ref: "runtime-boundary-non-attachable",
                   correlation_id: "corr-boundary-non-attachable",
                   request_id: "req-boundary-non-attachable"
                 },
                 allocation_ttl_ms: 250
               }),
               %{},
               target_descriptor: descriptor,
               adapter: BoundaryTestAdapter,
               adapter_opts: [store: store],
               room_id: "room-boundary-non-attachable",
               job_id: "job-boundary-non-attachable",
               participant_id: "worker-01"
             )

    assert Exception.message(error) =~ "attach metadata"
  end

  defp boundary_target do
    %{
      target_id: "target-boundary-1",
      capability_id: "codex.exec.session",
      runtime_driver: "asm",
      provider: "codex",
      workspace_root: "/srv/hive",
      execution_environment: %{
        "workspace_root" => "/srv/hive",
        "allowed_tools" => ["git.status"],
        "approval_posture" => "manual",
        "permission_mode" => "default"
      },
      provider_options: %{"model" => "gpt-5.4", "reasoning_effort" => "low"},
      boundary_request: %{
        boundary_session_id: "bnd-hive-room-1",
        backend_kind: :microvm,
        boundary_class: :leased_cell,
        attach: %{mode: :attachable, working_directory: "/srv/hive"},
        policy_intent: %{
          sandbox_level: :strict,
          egress: :restricted,
          approvals: :manual,
          allowed_tools: ["git.status", "git.push"],
          file_scope: "/srv/hive"
        },
        refs: %{
          target_id: "target-boundary-1",
          lease_ref: "lease-boundary-1",
          surface_ref: "surface-boundary-1",
          runtime_ref: "runtime-boundary-1",
          correlation_id: "corr-boundary-1",
          request_id: "req-boundary-1"
        },
        allocation_ttl_ms: 250
      },
      boundary_capability: %{
        "supported" => true,
        "boundary_classes" => ["leased_cell"],
        "attach_modes" => ["guest_bridge"],
        "checkpointing" => false
      }
    }
  end

  defp boundary_target_descriptor do
    TargetDescriptor.new!(%{
      target_id: "target-boundary-1",
      capability_id: "codex.exec.session",
      runtime_class: :session,
      version: "1.0.0",
      features: %{
        feature_ids: ["asm", "codex.exec.session"],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{},
      health: :healthy,
      location: %{mode: :beam, region: "local", workspace_root: "/srv/hive"},
      extensions: %{
        "boundary" => %{
          "supported" => true,
          "boundary_classes" => ["leased_cell"],
          "attach_modes" => ["guest_bridge"],
          "checkpointing" => false
        }
      }
    })
  end
end
