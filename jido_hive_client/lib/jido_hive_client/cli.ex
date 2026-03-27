defmodule JidoHiveClient.CLI do
  @moduledoc false

  alias JidoHiveClient.RelayWorker

  def main(args) do
    {:ok, _apps} = Application.ensure_all_started(:jido_hive_client)

    opts =
      args
      |> parse_args()
      |> normalize_cli_opts()

    {:ok, _pid} = RelayWorker.start_link(opts)
    Process.sleep(:infinity)
  end

  defp parse_args(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          url: :string,
          relay_topic: :string,
          workspace_id: :string,
          user_id: :string,
          participant_id: :string,
          participant_role: :string,
          target_id: :string,
          capability_id: :string,
          workspace_root: :string,
          provider: :string,
          model: :string,
          timeout_ms: :integer,
          cli_path: :string
        ]
      )

    if invalid != [] or rest != [] do
      raise ArgumentError,
            "invalid CLI arguments: #{inspect(invalid ++ Enum.map(rest, &{&1, nil}))}"
    end

    opts
  end

  defp normalize_cli_opts(opts) do
    workspace_id = Keyword.get(opts, :workspace_id, "workspace-local")

    [
      url: Keyword.get(opts, :url, "ws://127.0.0.1:4000/socket/websocket"),
      relay_topic: Keyword.get(opts, :relay_topic, "relay:#{workspace_id}"),
      workspace_id: workspace_id,
      user_id: Keyword.get(opts, :user_id, "user-local"),
      participant_id: Keyword.get(opts, :participant_id, "participant-local"),
      participant_role: Keyword.get(opts, :participant_role, "architect"),
      target_id: Keyword.get(opts, :target_id, "target-local"),
      capability_id: Keyword.get(opts, :capability_id, "codex.exec.session"),
      workspace_root: Keyword.get(opts, :workspace_root, File.cwd!()),
      executor:
        {JidoHiveClient.Executor.Session,
         [
           provider: parse_provider(Keyword.get(opts, :provider, "codex")),
           model: Keyword.get(opts, :model),
           timeout_ms: Keyword.get(opts, :timeout_ms),
           cli_path: Keyword.get(opts, :cli_path)
         ]}
    ]
  end

  defp parse_provider(provider) when is_binary(provider), do: String.to_atom(provider)
  defp parse_provider(provider) when is_atom(provider), do: provider
end
