defmodule JidoHiveServer.Publications.IntegrationGateway do
  @moduledoc false

  alias Jido.Integration.V2

  @behaviour JidoHiveServer.Publications.Gateway

  @impl true
  def invoke_publication(plan, input, opts)
      when is_map(plan) and is_map(input) and is_map(opts) do
    capability_id = plan.capability_id || plan["capability_id"]
    connection_id = opts[:connection_id] || opts["connection_id"]

    with {:ok, capability} <- V2.fetch_capability(capability_id) do
      invoke_opts =
        [
          connection_id: connection_id,
          actor_id: opts[:actor_id] || opts["actor_id"],
          tenant_id: opts[:tenant_id] || opts["tenant_id"],
          environment: :prod,
          allowed_operations: [capability_id],
          sandbox: capability.metadata.policy.sandbox
        ]
        |> maybe_put(:notion_client, opts[:notion_client] || opts["notion_client"])

      V2.invoke(capability_id, input, invoke_opts)
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
