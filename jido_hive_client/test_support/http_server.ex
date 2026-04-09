defmodule JidoHiveClient.TestHTTPServer do
  @moduledoc """
  Small TCP-backed HTTP server used by client tests to stub REST responses
  without introducing another web dependency into the package.
  """

  defstruct [:listen_socket, :port, :acceptor]

  def start_link(handler) when is_function(handler, 1) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    acceptor =
      spawn_link(fn ->
        accept_loop(listen_socket, handler)
      end)

    {:ok, %__MODULE__{listen_socket: listen_socket, port: port, acceptor: acceptor}}
  end

  def base_url(%__MODULE__{port: port}), do: "http://127.0.0.1:#{port}"

  def stop(%__MODULE__{acceptor: acceptor, listen_socket: listen_socket}) do
    Process.exit(acceptor, :shutdown)
    :gen_tcp.close(listen_socket)
    :ok
  end

  defp accept_loop(listen_socket, handler) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        spawn(fn -> handle_connection(socket, handler) end)
        accept_loop(listen_socket, handler)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp handle_connection(socket, handler) do
    {:ok, request} = read_request(socket, "")
    {status, headers, body} = handler.(request)
    response = response(status, headers, body)
    _ = :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp read_request(socket, acc) do
    with {:ok, data} <- :gen_tcp.recv(socket, 0, 5_000),
         next_acc = acc <> data do
      case parse_request(next_acc) do
        {:ok, request} -> {:ok, request}
        :more -> read_request(socket, next_acc)
      end
    end
  end

  defp parse_request(buffer) do
    case String.split(buffer, "\r\n\r\n", parts: 2) do
      [header_blob, body] -> build_request(header_blob, body)
      _other -> :more
    end
  end

  defp build_request(header_blob, body) do
    headers = parse_headers(header_blob)
    content_length = headers["content-length"] |> parse_integer(0)

    if byte_size(body) >= content_length do
      {:ok,
       %{
         method: request_method(header_blob),
         path: request_path(header_blob),
         headers: headers,
         body: binary_part(body, 0, content_length)
       }}
    else
      :more
    end
  end

  defp request_method(header_blob) do
    header_blob
    |> String.split("\r\n", parts: 2)
    |> hd()
    |> String.split(" ", parts: 3)
    |> Enum.at(0)
  end

  defp request_path(header_blob) do
    header_blob
    |> String.split("\r\n", parts: 2)
    |> hd()
    |> String.split(" ", parts: 3)
    |> Enum.at(1)
  end

  defp parse_headers(header_blob) do
    header_blob
    |> String.split("\r\n")
    |> tl()
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.downcase(key), String.trim(value))
        _other -> acc
      end
    end)
  end

  defp response(status, headers, body) do
    body = body || ""

    headers =
      headers
      |> Map.put_new("content-type", "application/json")
      |> Map.put("content-length", Integer.to_string(byte_size(body)))

    [
      "HTTP/1.1 #{status} #{reason_phrase(status)}\r\n",
      Enum.map(headers, fn {key, value} -> "#{key}: #{value}\r\n" end),
      "\r\n",
      body
    ]
  end

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _other -> default
    end
  end

  defp reason_phrase(200), do: "OK"
  defp reason_phrase(201), do: "Created"
  defp reason_phrase(404), do: "Not Found"
  defp reason_phrase(500), do: "Internal Server Error"
  defp reason_phrase(_status), do: "OK"
end
