defmodule JidoHiveServer.Connectors.WorkspaceSession.Handler do
  @moduledoc false
end

defmodule JidoHiveServer.Connectors.WorkspaceSession do
  @moduledoc """
  Provider-neutral session connector for relay-managed workspace targets.

  This is the authored session capability for Jido Hive. It describes the
  shared ASM-backed session surface without coupling the server to any vendor
  sample connector package.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  @connector_id "workspace_session"
  @operation_id "workspace.exec.session"

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: @connector_id,
      auth:
        AuthSpec.new!(%{
          binding_kind: :none,
          auth_type: :none,
          install: %{required: false},
          reauth: %{supported: false},
          requested_scopes: [],
          lease_fields: [],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Workspace Session",
          description: "Provider-neutral session capability backed by the ASM runtime bridge",
          category: "runtime",
          tags: ["workspace", "session", "asm"],
          docs_refs: [],
          maturity: :beta,
          publication: :internal
        }),
      operations: [
        OperationSpec.new!(%{
          operation_id: @operation_id,
          name: "exec_session",
          display_name: "Execute workspace session",
          description: "Runs a relay-managed workspace session turn through ASM",
          runtime_class: :session,
          transport_mode: :stdio,
          handler: JidoHiveServer.Connectors.WorkspaceSession.Handler,
          input_schema:
            Zoi.object(%{
              prompt: Zoi.string()
            }),
          output_schema:
            Zoi.object(%{
              reply: Zoi.string(),
              turn: Zoi.integer(),
              workspace: Zoi.string(),
              auth_binding: Zoi.string(),
              approval_mode: Zoi.atom()
            }),
          permissions: %{required_scopes: []},
          runtime: %{
            driver: "asm",
            provider: :session,
            options: %{}
          },
          policy: %{
            environment: %{allowed: [:dev, :test, :prod]},
            sandbox: %{
              level: :strict,
              egress: :restricted,
              approvals: :manual,
              file_scope: "/workspaces",
              allowed_tools: [@operation_id]
            }
          },
          upstream: %{protocol: :stdio},
          consumer_surface: %{
            mode: :common,
            normalized_id: @operation_id,
            action_name: "workspace_exec_session"
          },
          schema_policy: %{
            input: :defined,
            output: :defined
          },
          jido: %{action: %{name: "workspace_exec_session"}},
          metadata: %{
            runtime_family: %{
              session_affinity: :target,
              resumable: true,
              approval_required: true,
              stream_capable: true,
              lifecycle_owner: :asm,
              runtime_ref: :session
            }
          }
        })
      ],
      triggers: [],
      runtime_families: [:session]
    })
  end
end
