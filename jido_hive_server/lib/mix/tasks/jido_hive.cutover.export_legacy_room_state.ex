defmodule Mix.Tasks.JidoHive.Cutover.ExportLegacyRoomState do
  @moduledoc false
  @shortdoc "Exports persisted room-core rows before the canonical cutover reset"

  use Mix.Task

  alias Ecto.Adapters.SQL
  alias JidoHiveServer.Repo

  @tables ~w[room_snapshots room_events room_runs run_operations publication_runs]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [output: :string]
      )

    output_path =
      Keyword.get_lazy(opts, :output, fn ->
        timestamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        Path.join(["tmp", "cutover", "legacy_room_state_#{sanitize(timestamp)}.json"])
      end)

    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      source_app: "jido_hive_server",
      tables:
        Enum.into(@tables, %{}, fn table ->
          {table, export_table(table)}
        end)
    }

    output_path
    |> Path.expand()
    |> tap(&File.mkdir_p!(Path.dirname(&1)))
    |> then(fn path ->
      File.write!(path, Jason.encode_to_iodata!(payload, pretty: true))
      Mix.shell().info("exported legacy room state to #{path}")
    end)
  end

  defp export_table(table) do
    if table_exists?(table) do
      query = SQL.query!(Repo, "SELECT * FROM #{table}", [])
      Enum.map(query.rows, &export_row(query.columns, &1))
    else
      []
    end
  end

  defp export_row(columns, row) do
    columns
    |> Enum.zip(row)
    |> Enum.into(%{}, fn {column, value} -> {column, normalize(value)} end)
  end

  defp table_exists?(table) do
    query =
      SQL.query!(
        Repo,
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [table]
      )

    query.num_rows > 0
  end

  defp normalize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value

  defp sanitize(value) do
    value
    |> String.replace(":", "-")
    |> String.replace(~r/[^A-Za-z0-9._-]/u, "_")
  end
end
