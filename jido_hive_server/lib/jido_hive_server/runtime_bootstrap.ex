defmodule JidoHiveServer.RuntimeBootstrap do
  @moduledoc false

  use GenServer

  alias Jido.Os.SystemInstanceSupervisor
  alias Jido.Os.SystemInstanceSupervisor.Instance

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def instance_id do
    GenServer.call(@name, :instance_id)
  end

  def ensure_instance do
    GenServer.call(@name, :ensure_instance)
  end

  @impl true
  def init(_opts) do
    with {:ok, _apps} <- Application.ensure_all_started(:jido_os),
         {:ok, instance_id} <- ensure_default_instance() do
      {:ok, %{instance_id: instance_id}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:instance_id, _from, state), do: {:reply, state.instance_id, state}

  @impl true
  def handle_call(:ensure_instance, _from, state) do
    {:reply, ensure_instance_started(state.instance_id), state}
  end

  defp ensure_default_instance do
    instance_id = Application.fetch_env!(:jido_hive_server, :default_instance_id)

    case ensure_instance_started(instance_id) do
      :ok -> {:ok, instance_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_instance_started(instance_id) do
    context = bootstrap_context(instance_id)

    case SystemInstanceSupervisor.lookup_instance(instance_id) do
      {:ok, _pid} -> ensure_instance_ready(instance_id)
      :error -> start_instance(instance_id, context)
    end
  end

  defp start_instance(instance_id, context) do
    case SystemInstanceSupervisor.start_instance(instance_id, context) do
      {:ok, _pid} -> ensure_instance_ready(instance_id)
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_instance_ready(instance_id) do
    if wait_until(fn -> Instance.ready?(instance_id) end) do
      :ok
    else
      {:error, :instance_not_ready}
    end
  end

  defp bootstrap_context(instance_id) do
    %{
      instance_id: instance_id,
      actor_id: "system:jido_hive_server_boot",
      correlation_id: "jido-hive-server-bootstrap",
      request_id: "jido-hive-server-bootstrap"
    }
  end

  defp wait_until(fun, attempts \\ 40)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end
end
