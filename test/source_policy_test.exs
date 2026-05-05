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
    "list_to_" <> "atom",
    "list_to_existing_" <> "atom",
    ":" <> <<35, 123>>,
    Enum.join(["Module", ".concat"]),
    "Reg" <> "ex",
    "reg" <> "ex",
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

    token_hits =
      @forbidden_tokens
      |> Enum.filter(&String.contains?(content, &1))
      |> Enum.map(fn token -> "#{Path.relative_to(path, @root)} contains #{inspect(token)}" end)

    dynamic_quoted_atom_hits(path, content) ++ token_hits
  end

  defp dynamic_quoted_atom_hits(path, content) do
    if dynamic_quoted_atom_interpolation?(String.to_charlist(content)) do
      ["#{Path.relative_to(path, @root)} contains dynamic quoted atom interpolation"]
    else
      []
    end
  end

  defp dynamic_quoted_atom_interpolation?([?:, ?" | rest]) do
    quoted_atom_interpolates?(rest) or dynamic_quoted_atom_interpolation?(rest)
  end

  defp dynamic_quoted_atom_interpolation?([_char | rest]),
    do: dynamic_quoted_atom_interpolation?(rest)

  defp dynamic_quoted_atom_interpolation?([]), do: false

  defp quoted_atom_interpolates?([?", _next | _rest]), do: false
  defp quoted_atom_interpolates?([?#, ?{ | _rest]), do: true
  defp quoted_atom_interpolates?([?\\, _escaped | rest]), do: quoted_atom_interpolates?(rest)
  defp quoted_atom_interpolates?([_char | rest]), do: quoted_atom_interpolates?(rest)
  defp quoted_atom_interpolates?([]), do: false

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
