defmodule JidoHiveSourcePolicyTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @excluded_dirs MapSet.new([".git", "_build", "deps", "doc", "node_modules"])
  @code_extensions MapSet.new([
                     ".bash",
                     ".c",
                     ".eex",
                     ".erl",
                     ".ex",
                     ".exs",
                     ".h",
                     ".heex",
                     ".hrl",
                     ".js",
                     ".jsx",
                     ".py",
                     ".sh",
                     ".ts",
                     ".tsx",
                     ".zsh"
                   ])
  @code_basenames MapSet.new(["justfile", "Makefile"])
  @forbidden_tokens [
    "String.to_" <> "atom",
    "String.to_existing_" <> "atom",
    "binary_to_" <> "atom",
    "binary_to_existing_" <> "atom",
    ":" <> <<35, 123>>,
    "Reg" <> "ex",
    "~" <> "r",
    ":re" <> ".",
    "String." <> "match",
    "Reg" <> "Exp",
    "reg" <> "exp",
    "re." <> "compile",
    "import " <> "re"
  ]

  test "code paths avoid dynamic atoms and pattern engines" do
    hits =
      @root
      |> source_files()
      |> Enum.flat_map(&token_hits/1)

    assert hits == []
  end

  defp token_hits(path) do
    content = File.read!(path)

    @forbidden_tokens
    |> Enum.filter(&String.contains?(content, &1))
    |> Enum.map(fn token -> "#{Path.relative_to(path, @root)} contains #{inspect(token)}" end)
  end

  defp source_files(root), do: source_files(root, [])

  defp source_files(path, acc) do
    cond do
      File.dir?(path) ->
        if excluded_dir?(path) do
          acc
        else
          path
          |> File.ls!()
          |> Enum.map(&Path.join(path, &1))
          |> Enum.reduce(acc, &source_files/2)
        end

      code_file?(path) ->
        [path | acc]

      true ->
        acc
    end
  end

  defp excluded_dir?(path) do
    MapSet.member?(@excluded_dirs, Path.basename(path)) or
      Path.relative_to(path, @root) == "jido_hive_web/priv/static/assets"
  end

  defp code_file?(path) do
    MapSet.member?(@code_extensions, Path.extname(path)) or
      MapSet.member?(@code_basenames, Path.basename(path))
  end
end
