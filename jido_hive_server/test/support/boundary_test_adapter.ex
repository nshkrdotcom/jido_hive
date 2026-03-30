defmodule JidoHiveServer.TestSupport.BoundaryTestAdapter do
  @moduledoc false
  @behaviour Jido.BoundaryBridge.Adapter

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{descriptors: %{}, calls: []} end)
  end

  def put_descriptor(store, boundary_session_id, descriptor) do
    Agent.update(store, fn state ->
      put_in(state, [:descriptors, boundary_session_id], descriptor)
    end)
  end

  def calls(store) do
    Agent.get(store, &Enum.reverse(&1.calls))
  end

  @impl true
  def allocate(payload, opts) do
    resolve_descriptor(:allocate, payload, opts)
  end

  @impl true
  def reopen(payload, opts) do
    resolve_descriptor(:reopen, payload, opts)
  end

  @impl true
  def fetch_status(boundary_session_id, opts) do
    store = Keyword.fetch!(opts, :store)

    case Agent.get(store, &get_in(&1, [:descriptors, boundary_session_id])) do
      nil -> {:error, %{message: "unknown boundary_session_id"}}
      descriptor -> {:ok, descriptor}
    end
  end

  @impl true
  def claim(boundary_session_id, payload, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      case get_in(state, [:descriptors, boundary_session_id]) do
        nil ->
          {{:error, %{message: "unknown boundary_session_id"}}, state}

        descriptor ->
          claimed =
            descriptor
            |> Map.put(:status, :ready)
            |> Map.put(:attach_ready?, true)
            |> Map.update(:metadata, %{}, fn metadata ->
              metadata
              |> Map.put(:runtime_owner, Map.get(payload, :runtime_owner))
              |> Map.put(:runtime_ref, Map.get(payload, :runtime_ref))
            end)

          {{:ok, claimed},
           state
           |> put_in([:descriptors, boundary_session_id], claimed)
           |> update_in([:calls], &[{:claim, boundary_session_id} | &1])}
      end
    end)
  end

  @impl true
  def heartbeat(boundary_session_id, payload, opts) do
    claim(boundary_session_id, payload, opts)
  end

  @impl true
  def stop(_boundary_session_id, _opts), do: :ok

  defp resolve_descriptor(call, payload, opts) do
    store = Keyword.fetch!(opts, :store)

    Agent.get_and_update(store, fn state ->
      boundary_session_id = Map.fetch!(payload, :boundary_session_id)

      descriptor =
        Map.get_lazy(state.descriptors, boundary_session_id, fn ->
          default_descriptor(payload)
        end)

      {{:ok, descriptor},
       state
       |> put_in([:descriptors, boundary_session_id], descriptor)
       |> update_in([:calls], &[{call, boundary_session_id} | &1])}
    end)
  end

  defp default_descriptor(payload) do
    target_id = get_in(payload, [:refs, :target_id]) || "target-#{payload.boundary_session_id}"
    lease_ref = get_in(payload, [:refs, :lease_ref])
    surface_ref = get_in(payload, [:refs, :surface_ref])

    %{
      descriptor_version: 1,
      boundary_session_id: payload.boundary_session_id,
      backend_kind: payload.backend_kind,
      boundary_class: payload.boundary_class,
      status: :ready,
      attach_ready?: true,
      workspace: %{
        workspace_root: get_in(payload, [:attach, :working_directory]),
        snapshot_ref: Map.get(payload, :checkpoint_id),
        artifact_namespace: get_in(payload, [:refs, :request_id])
      },
      attach: %{
        mode: :attachable,
        execution_surface: execution_surface(target_id, lease_ref, surface_ref, payload),
        working_directory: get_in(payload, [:attach, :working_directory])
      },
      checkpointing: %{
        supported?: is_binary(Map.get(payload, :checkpoint_id)),
        last_checkpoint_id: Map.get(payload, :checkpoint_id)
      },
      policy_intent_echo: Map.get(payload, :policy_intent, %{}),
      refs: Map.get(payload, :refs, %{}),
      extensions: Map.get(payload, :extensions, %{}),
      metadata: Map.get(payload, :metadata, %{})
    }
  end

  defp normalize_boundary_class(value) when is_atom(value), do: value
  defp normalize_boundary_class(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_boundary_class(_value), do: nil

  defp execution_surface(target_id, lease_ref, surface_ref, payload) do
    {:ok, surface} =
      CliSubprocessCore.ExecutionSurface.new(%{
        surface_kind: :guest_bridge,
        transport_options: [
          endpoint: %{kind: :unix_socket, path: "/tmp/#{target_id}.sock"},
          bridge_ref: "bridge-#{target_id}",
          bridge_profile: "core_cli_transport",
          supported_protocol_versions: [1]
        ],
        target_id: target_id,
        lease_ref: lease_ref,
        surface_ref: surface_ref,
        boundary_class: normalize_boundary_class(payload.boundary_class),
        observability: %{}
      })

    surface
  end
end
