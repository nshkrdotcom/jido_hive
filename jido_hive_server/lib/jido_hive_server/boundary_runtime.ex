defmodule JidoHiveServer.BoundaryRuntime do
  @moduledoc false

  alias Jido.BoundaryBridge
  alias Jido.BoundaryBridge.Adapters.JidoOs
  alias Jido.Harness.Error
  alias Jido.Integration.V2
  alias Jido.Integration.V2.TargetDescriptor
  alias JidoHiveServer.Runtime

  @type prepared_session :: %{
          session: map(),
          boundary_sessions: map()
        }

  @spec boundary_capability(map()) :: map() | nil
  def boundary_capability(target) when is_map(target) do
    case map_value(target, :boundary_capability) do
      %{} = capability ->
        capability

      _other ->
        derive_boundary_capability(
          map_value(target, :boundary_request) || map_value(target, :boundary_reopen_request)
        )
    end
  end

  @spec prepare_session(map(), map(), keyword()) ::
          {:ok, prepared_session()} | {:error, Exception.t()}
  def prepare_session(target, boundary_sessions, opts \\ [])
      when is_map(target) and is_map(boundary_sessions) and is_list(opts) do
    with {:ok, target_descriptor} <- fetch_target_descriptor(target, opts),
         {:ok, boundary_capability} <-
           fetch_boundary_capability(target, target_descriptor, boundary_sessions),
         {:ok, prepared_boundary} <-
           maybe_prepare_boundary(target, boundary_sessions, boundary_capability, opts) do
      {:ok,
       %{
         session: apply_boundary_session(base_session(target), prepared_boundary),
         boundary_sessions: merge_boundary_sessions(boundary_sessions, target, prepared_boundary)
       }}
    end
  end

  defp fetch_target_descriptor(target, opts) do
    case Keyword.get(opts, :target_descriptor) do
      %TargetDescriptor{} = descriptor ->
        {:ok, descriptor}

      nil ->
        fetch_target_fun = Keyword.get(opts, :fetch_target, &V2.fetch_target/1)
        target_id = Keyword.get(opts, :target_id) || fetch_target_id(target)

        case fetch_target_fun.(target_id) do
          {:ok, %TargetDescriptor{} = descriptor} ->
            {:ok, descriptor}

          :error ->
            {:error,
             Error.validation_error("target descriptor not found", %{target_id: target_id})}

          {:error, reason} ->
            {:error, normalize_error(reason)}
        end

      other ->
        {:error,
         Error.validation_error("invalid target descriptor", %{target_descriptor: inspect(other)})}
    end
  end

  defp fetch_boundary_capability(target, descriptor, boundary_sessions) do
    target_id = fetch_target_id(target)

    case {TargetDescriptor.authored_boundary_capability(descriptor),
          has_boundary_state?(boundary_sessions, target_id), has_boundary_request?(target)} do
      {nil, false, false} ->
        {:ok, nil}

      {nil, _retained?, _requested?} ->
        {:error,
         Error.validation_error(
           "boundary capability must be advertised through the target descriptor extension",
           %{target_id: target_id}
         )}

      {%{supported: false}, true, _requested?} ->
        {:error,
         Error.validation_error(
           "target descriptor does not advertise boundary support for retained boundary state",
           %{target_id: target_id}
         )}

      {%{supported: false}, _retained?, true} ->
        {:error,
         Error.validation_error(
           "target descriptor does not advertise boundary support for the requested boundary",
           %{target_id: target_id}
         )}

      {capability, _retained?, _requested?} ->
        {:ok, capability}
    end
  end

  defp maybe_prepare_boundary(_target, _boundary_sessions, nil, _opts), do: {:ok, nil}

  defp maybe_prepare_boundary(target, boundary_sessions, boundary_capability, opts) do
    if boundary_capability.supported do
      prepare_boundary(target, boundary_sessions, opts)
    else
      {:ok, nil}
    end
  end

  defp prepare_boundary(target, boundary_sessions, opts) do
    target_id = fetch_target_id(target)
    retained_state = fetch_boundary_state(boundary_sessions, target_id)
    adapter = Keyword.get(opts, :adapter, JidoOs)
    adapter_opts = Keyword.get(opts, :adapter_opts, default_adapter_opts(opts))
    runtime_owner = Keyword.get(opts, :runtime_owner, "jido_hive_server")
    runtime_ref = boundary_runtime_ref(target, opts)

    cond do
      retained_state != nil ->
        reopen_request = reopen_request_for_turn(retained_state, opts)

        with {:ok, descriptor} <-
               BoundaryBridge.reopen(
                 reopen_request,
                 boundary_bridge_opts(adapter, adapter_opts)
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, descriptor} <-
               BoundaryBridge.claim(
                 descriptor,
                 boundary_bridge_opts(adapter, adapter_opts,
                   runtime_owner: runtime_owner,
                   runtime_ref: runtime_ref
                 )
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, attach_metadata} <- BoundaryBridge.project_attach_metadata(descriptor),
             :ok <- ensure_attach_metadata(descriptor, attach_metadata) do
          {:ok,
           %{
             descriptor: descriptor,
             attach_metadata: attach_metadata,
             state: boundary_state(retained_state, descriptor, reopen_request)
           }}
        end

      boundary_reopen_request = normalize_mapish(map_value(target, :boundary_reopen_request)) ->
        with {:ok, descriptor} <-
               BoundaryBridge.reopen(
                 boundary_reopen_request,
                 boundary_bridge_opts(adapter, adapter_opts)
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, descriptor} <-
               BoundaryBridge.claim(
                 descriptor,
                 boundary_bridge_opts(adapter, adapter_opts,
                   runtime_owner: runtime_owner,
                   runtime_ref: runtime_ref
                 )
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, attach_metadata} <- BoundaryBridge.project_attach_metadata(descriptor),
             :ok <- ensure_attach_metadata(descriptor, attach_metadata) do
          {:ok,
           %{
             descriptor: descriptor,
             attach_metadata: attach_metadata,
             state: boundary_state(%{}, descriptor, boundary_reopen_request)
           }}
        end

      boundary_request = normalize_mapish(map_value(target, :boundary_request)) ->
        with {:ok, descriptor} <-
               BoundaryBridge.allocate(
                 boundary_request,
                 boundary_bridge_opts(adapter, adapter_opts)
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, descriptor} <-
               BoundaryBridge.claim(
                 descriptor,
                 boundary_bridge_opts(adapter, adapter_opts,
                   runtime_owner: runtime_owner,
                   runtime_ref: runtime_ref
                 )
               ),
             :ok <- ensure_supported_boundary_descriptor(descriptor),
             {:ok, attach_metadata} <- BoundaryBridge.project_attach_metadata(descriptor),
             :ok <- ensure_attach_metadata(descriptor, attach_metadata) do
          reopen_request =
            reopen_request_from_descriptor(target, descriptor, boundary_request, opts)

          {:ok,
           %{
             descriptor: descriptor,
             attach_metadata: attach_metadata,
             state: boundary_state(%{}, descriptor, reopen_request)
           }}
        end

      true ->
        {:ok, nil}
    end
  end

  defp ensure_supported_boundary_descriptor(%{descriptor_version: 1}), do: :ok

  defp ensure_supported_boundary_descriptor(%{descriptor_version: version}) do
    {:error,
     Error.validation_error("unsupported boundary descriptor_version", %{
       descriptor_version: version,
       supported_versions: [1]
     })}
  end

  defp ensure_attach_metadata(_descriptor, %{execution_surface: _execution_surface}), do: :ok

  defp ensure_attach_metadata(descriptor, nil) do
    {:error,
     Error.validation_error("boundary attach metadata is required for Hive session execution", %{
       details: %{
         boundary_session_id: descriptor.boundary_session_id,
         attach_mode: descriptor.attach.mode
       }
     })}
  end

  defp base_session(target) do
    %{
      "runtime_driver" => map_value(target, :runtime_driver) || "asm",
      "provider" => map_value(target, :provider) || "codex",
      "workspace_root" => map_value(target, :workspace_root),
      "execution_surface" => map_value(target, :execution_surface),
      "execution_environment" => map_value(target, :execution_environment),
      "provider_options" => map_value(target, :provider_options)
    }
    |> compact_map()
  end

  defp apply_boundary_session(session, nil), do: session

  defp apply_boundary_session(
         session,
         %{descriptor: descriptor, attach_metadata: attach_metadata, state: state}
       ) do
    execution_environment =
      session
      |> Map.get("execution_environment", %{})
      |> normalize_mapish()
      |> maybe_put(
        "workspace_root",
        attach_metadata.working_directory || descriptor.workspace.workspace_root
      )
      |> empty_map_to_nil()

    session
    |> maybe_put(
      "workspace_root",
      attach_metadata.working_directory || descriptor.workspace.workspace_root
    )
    |> Map.put("execution_surface", normalize_value(attach_metadata.execution_surface))
    |> maybe_put("execution_environment", execution_environment)
    |> Map.put("boundary", normalize_value(state))
  end

  defp merge_boundary_sessions(boundary_sessions, _target, nil), do: boundary_sessions

  defp merge_boundary_sessions(boundary_sessions, target, %{state: state}) do
    Map.put(boundary_sessions, fetch_target_id(target), normalize_value(state))
  end

  defp boundary_state(existing_state, descriptor, reopen_request) do
    existing_state
    |> normalize_mapish()
    |> Map.put("boundary_session_id", descriptor.boundary_session_id)
    |> Map.put("descriptor", normalize_value(Map.from_struct(descriptor)))
    |> Map.put("reopen_request", normalize_value(reopen_request))
  end

  defp reopen_request_from_descriptor(target, descriptor, source_request, opts) do
    refs =
      source_request
      |> map_value(:refs)
      |> normalize_mapish()
      |> Kernel.||(%{})
      |> Map.put("target_id", fetch_target_id(target))
      |> maybe_put("runtime_ref", boundary_runtime_ref(target, opts))
      |> maybe_put("correlation_id", Keyword.get(opts, :correlation_id))
      |> maybe_put("request_id", Keyword.get(opts, :request_id))

    %{
      boundary_session_id: descriptor.boundary_session_id,
      backend_kind: descriptor.backend_kind,
      boundary_class: descriptor.boundary_class,
      checkpoint_id: descriptor.checkpointing.last_checkpoint_id,
      attach: %{
        mode: descriptor.attach.mode,
        working_directory:
          descriptor.attach.working_directory || descriptor.workspace.workspace_root
      },
      refs: refs
    }
    |> maybe_put(:extensions, normalize_mapish(map_value(source_request, :extensions)))
    |> maybe_put(:metadata, normalize_mapish(map_value(source_request, :metadata)))
  end

  defp reopen_request_for_turn(retained_state, opts) do
    retained_state
    |> normalize_mapish()
    |> Map.fetch!("reopen_request")
    |> normalize_mapish()
    |> update_refs_for_turn(opts)
  end

  defp update_refs_for_turn(reopen_request, opts) do
    refs =
      reopen_request
      |> Map.get("refs", %{})
      |> normalize_mapish()
      |> Kernel.||(%{})
      |> maybe_put("correlation_id", Keyword.get(opts, :correlation_id))
      |> maybe_put("request_id", Keyword.get(opts, :request_id))

    Map.put(reopen_request, "refs", refs)
  end

  defp default_adapter_opts(opts) do
    actor_id = Keyword.get(opts, :actor_id, "system:jido_hive_server")

    [
      instance_id: Runtime.instance_id(),
      actor_id: actor_id,
      attrs:
        Runtime.context_for(actor_id, %{
          room_id: Keyword.get(opts, :room_id),
          job_id: Keyword.get(opts, :job_id),
          participant_id: Keyword.get(opts, :participant_id),
          target_id: Keyword.get(opts, :target_id)
        })
    ]
  end

  defp boundary_runtime_ref(target, opts) do
    Keyword.get(opts, :runtime_ref) ||
      Keyword.get(opts, :job_id) ||
      "#{Keyword.get(opts, :room_id)}:#{fetch_target_id(target)}"
  end

  defp boundary_bridge_opts(adapter, adapter_opts, extra_opts \\ []) do
    []
    |> maybe_put(:adapter, adapter)
    |> Keyword.put(:adapter_opts, adapter_opts)
    |> Keyword.merge(extra_opts)
  end

  defp fetch_boundary_state(boundary_sessions, target_id) when is_map(boundary_sessions) do
    Map.get(boundary_sessions, target_id) ||
      Map.get(boundary_sessions, to_string(target_id))
  end

  defp has_boundary_state?(boundary_sessions, target_id) do
    fetch_boundary_state(boundary_sessions, target_id) != nil
  end

  defp has_boundary_request?(target) do
    map_value(target, :boundary_request) != nil ||
      map_value(target, :boundary_reopen_request) != nil
  end

  defp fetch_target_id(target) do
    map_value(target, :target_id) || raise ArgumentError, "target_id is required"
  end

  defp derive_boundary_capability(nil), do: nil

  defp derive_boundary_capability(request) do
    request = normalize_mapish(request) || %{}
    attach = request |> map_value(:attach) |> normalize_mapish() || %{}

    %{
      "supported" => true,
      "boundary_classes" => boundary_classes(request),
      "attach_modes" => [attach_mode(attach)],
      "checkpointing" => present?(map_value(request, :checkpoint_id))
    }
  end

  defp boundary_classes(request) do
    case map_value(request, :boundary_class) do
      nil -> []
      value when is_binary(value) -> [value]
      value when is_atom(value) -> [Atom.to_string(value)]
      _other -> []
    end
  end

  defp attach_mode(attach) do
    case map_value(attach, :mode) do
      value when value in [:attachable, "attachable"] -> "guest_bridge"
      _other -> "none"
    end
  end

  defp normalize_error(error) when is_exception(error), do: error
  defp normalize_error(error), do: RuntimeError.exception(inspect(error))

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp map_value(_map, _key), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value) when is_map(map), do: Map.put(map, key, value)
  defp maybe_put(keyword, _key, nil) when is_list(keyword), do: keyword
  defp maybe_put(keyword, key, value) when is_list(keyword), do: Keyword.put(keyword, key, value)

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_mapish(nil), do: nil
  defp normalize_mapish(value) when is_map(value), do: value
  defp normalize_mapish(value) when is_list(value), do: Map.new(value)
  defp normalize_mapish(_value), do: nil

  defp empty_map_to_nil(map) when is_map(map) and map_size(map) == 0, do: nil
  defp empty_map_to_nil(map), do: map

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(value) when is_integer(value), do: value
  defp normalize_value(value) when is_float(value), do: value
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_value(%_{} = value) do
    value
    |> Map.from_struct()
    |> normalize_value()
  end

  defp normalize_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
  end

  defp normalize_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Map.new(value, fn {key, nested_value} -> {to_string(key), normalize_value(nested_value)} end)
    else
      Enum.map(value, &normalize_value/1)
    end
  end

  defp normalize_value(value), do: value

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true
end
