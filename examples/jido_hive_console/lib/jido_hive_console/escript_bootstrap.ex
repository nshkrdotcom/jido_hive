defmodule JidoHiveConsole.EscriptBootstrap do
  @moduledoc false

  alias JidoHiveClient.Operator

  @ex_ratatui_archive_prefix "ex_ratatui/"
  @release_ets_prefix "tzdata/priv/release_ets/"
  @tzdata_app :tzdata
  @zip_name ~c"escript.zip"

  @spec start_console_dependencies() :: :ok | {:error, term()}
  def start_console_dependencies do
    case configure_tzdata() do
      :ok -> configure_ex_ratatui()
      {:error, _reason} = error -> error
    end
  end

  defp configure_tzdata do
    data_dir = tzdata_data_dir()
    release_dir = Path.join(data_dir, "release_ets")

    File.mkdir_p!(release_dir)
    Application.put_env(@tzdata_app, :autoupdate, :disabled, persistent: true)
    Application.put_env(@tzdata_app, :data_dir, data_dir, persistent: true)

    if tzdata_release_files_present?(release_dir) do
      :ok
    else
      seed_tzdata_release_files(release_dir)
    end
  end

  defp seed_tzdata_release_files(release_dir) do
    case copy_release_files_from_installed_priv(release_dir) do
      :ok ->
        :ok

      :error ->
        case copy_release_files_from_escript_archive(release_dir) do
          :ok ->
            :ok

          {:error, :missing_release_ets_in_archive} ->
            {:error, {:missing_tzdata_release_files, release_dir}}

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp configure_ex_ratatui do
    ex_ratatui_dir = ex_ratatui_app_dir()
    ebin_dir = Path.join(ex_ratatui_dir, "ebin")
    native_dir = Path.join(ex_ratatui_dir, "priv/native")

    with {:ok, archive} <- escript_archive(),
         :ok <- extract_ex_ratatui_app_from_archive(archive, ex_ratatui_dir),
         true <- File.dir?(ebin_dir),
         true <- File.dir?(native_dir),
         :ok <- add_code_path(ebin_dir) do
      :ok
    else
      {:error, :not_running_from_escript} -> :ok
      false -> {:error, {:missing_ex_ratatui_escript_files, ex_ratatui_dir}}
      {:error, _reason} = error -> error
    end
  end

  defp copy_release_files_from_installed_priv(release_dir) do
    source_dir = Application.app_dir(@tzdata_app, "priv/release_ets")

    if File.dir?(source_dir) do
      source_dir
      |> File.ls!()
      |> Enum.filter(&release_ets_filename?/1)
      |> Enum.each(fn filename ->
        File.cp!(Path.join(source_dir, filename), Path.join(release_dir, filename))
      end)

      :ok
    else
      :error
    end
  end

  defp copy_release_files_from_escript_archive(release_dir) do
    with {:ok, archive} <- escript_archive(),
         {:ok, copied} <- copy_release_files_from_archive_binary(archive, release_dir),
         true <- copied > 0 do
      :ok
    else
      false -> {:error, :missing_release_ets_in_archive}
      {:error, _reason} = error -> error
    end
  end

  defp escript_archive do
    script_name = :escript.script_name()

    with true <- is_list(script_name),
         {:ok, sections} <- :escript.extract(script_name, []),
         {:archive, archive} when is_binary(archive) <- List.keyfind(sections, :archive, 0) do
      {:ok, archive}
    else
      false -> {:error, :not_running_from_escript}
      {:error, _reason} = error -> error
      nil -> {:error, :missing_escript_archive}
    end
  end

  defp copy_release_files_from_archive_binary(archive, release_dir) do
    :zip.foldl(
      fn name, _get_info, get_bin, copied ->
        archive_path = List.to_string(name)

        if release_ets_archive_path?(archive_path) do
          filename = Path.basename(archive_path)
          File.write!(Path.join(release_dir, filename), get_bin.())
          copied + 1
        else
          copied
        end
      end,
      0,
      {@zip_name, archive}
    )
  end

  defp extract_ex_ratatui_app_from_archive(archive, ex_ratatui_dir) do
    File.rm_rf!(ex_ratatui_dir)
    File.mkdir_p!(ex_ratatui_dir)

    with {:ok, copied} <-
           copy_prefixed_archive_files_to_dir(archive, @ex_ratatui_archive_prefix, ex_ratatui_dir),
         true <- copied > 0 do
      :ok
    else
      false -> {:error, :missing_ex_ratatui_files_in_archive}
      {:error, _reason} = error -> error
    end
  end

  defp copy_prefixed_archive_files_to_dir(archive, prefix, target_dir) do
    :zip.foldl(
      fn name, _get_info, get_bin, copied ->
        archive_path = List.to_string(name)

        if String.starts_with?(archive_path, prefix) do
          relative_path = String.replace_prefix(archive_path, prefix, "")
          target_path = Path.join(target_dir, relative_path)
          File.mkdir_p!(Path.dirname(target_path))
          File.write!(target_path, get_bin.())
          copied + 1
        else
          copied
        end
      end,
      0,
      {@zip_name, archive}
    )
  end

  defp add_code_path(path) do
    case :code.add_patha(String.to_charlist(path)) do
      true -> :ok
      {:error, reason} -> {:error, {:code_path_add_failed, path, reason}}
    end
  end

  defp tzdata_data_dir do
    Path.join(Operator.config_dir(), "tzdata")
  end

  defp ex_ratatui_app_dir do
    Path.join(Operator.config_dir(), "escript_apps/ex_ratatui")
  end

  defp tzdata_release_files_present?(release_dir) do
    release_dir
    |> File.ls()
    |> case do
      {:ok, filenames} -> Enum.any?(filenames, &release_ets_filename?/1)
      {:error, _reason} -> false
    end
  end

  defp release_ets_archive_path?(path) do
    String.starts_with?(path, @release_ets_prefix) and release_ets_filename?(Path.basename(path))
  end

  defp release_ets_filename?(filename) do
    String.match?(filename, ~r/^2\d{3}[a-z]\.v\d+\.ets$/)
  end
end
