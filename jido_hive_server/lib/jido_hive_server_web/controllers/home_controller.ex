defmodule JidoHiveServerWeb.HomeController do
  use JidoHiveServerWeb, :controller

  @repo_url "https://github.com/nshkrdotcom/jido_hive"
  @prod_host "jido-hive-server-test.app.nsai.online"

  def index(conn, _params) do
    render_response(conn, :ok, "Jido Hive server is online.", nil)
  end

  def not_found(conn, %{"path" => ["api" | _]}) do
    render_json_not_found(conn)
  end

  def not_found(conn, %{"path" => path}) do
    missing_path = "/" <> Enum.join(path, "/")
    render_response(conn, :not_found, "That route does not exist on this server.", missing_path)
  end

  defp render_response(conn, status, summary, missing_path) do
    if wants_json?(conn) do
      render_json(conn, status, summary, missing_path)
    else
      render_html(conn, status, summary, missing_path)
    end
  end

  defp render_html(conn, status, summary, missing_path) do
    urls = endpoint_urls()

    conn
    |> put_status(status)
    |> put_secure_browser_headers()
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-robots-tag", "noindex")
    |> html(html_document(status, summary, missing_path, urls))
  end

  defp render_json(conn, status, summary, missing_path) do
    urls = endpoint_urls()

    conn
    |> put_status(status)
    |> json(%{
      name: "Jido Hive Server",
      status: Atom.to_string(status),
      message: summary,
      path: missing_path || "/",
      repo_url: @repo_url,
      endpoints: %{
        base_url: urls.base_url,
        api_base: urls.api_base,
        websocket: urls.websocket
      },
      demo: %{
        strategy: "round_robin",
        max_clients: 39,
        planned_turn_formula: "participant_count * 3"
      },
      helpers: %{
        local: %{
          control: "bin/hive-control",
          clients: "bin/hive-clients",
          worker: "bin/client-worker --worker-index 1",
          api: "setup/hive live-demo --participant-count 2"
        },
        prod: %{
          control: "bin/hive-control --prod",
          clients: "bin/hive-clients --prod",
          worker: "bin/client-worker --prod --worker-index 1",
          api: "setup/hive --prod live-demo --participant-count 2"
        }
      }
    })
  end

  defp render_json_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Not Found"}})
  end

  defp wants_json?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "application/json"))
  end

  defp endpoint_urls do
    base_uri =
      JidoHiveServerWeb.Endpoint.url()
      |> URI.parse()
      |> Map.put(:path, nil)
      |> Map.put(:query, nil)
      |> Map.put(:fragment, nil)

    %{
      base_url: URI.to_string(base_uri),
      api_base: URI.to_string(%{base_uri | path: "/api"}),
      websocket:
        URI.to_string(%{
          base_uri
          | scheme: websocket_scheme(base_uri.scheme),
            path: "/socket/websocket"
        })
    }
  end

  defp websocket_scheme("https"), do: "wss"
  defp websocket_scheme(_scheme), do: "ws"

  defp html_document(status, summary, missing_path, urls) do
    status_label =
      case status do
        :ok -> "Live Endpoint"
        :not_found -> "Route Not Found"
      end

    local_commands =
      Enum.join(
        [
          "bin/hive-control",
          "bin/hive-clients",
          "bin/client-worker --worker-index 1",
          "bin/client-worker --worker-index 2",
          "setup/hive live-demo --participant-count 2"
        ],
        "\n"
      )

    prod_commands =
      Enum.join(
        [
          "bin/hive-control --prod",
          "bin/hive-clients --prod",
          "bin/client-worker --prod --worker-index 1",
          "bin/client-worker --prod --worker-index 2",
          "setup/hive --prod live-demo --participant-count 2"
        ],
        "\n"
      )

    path_html =
      case missing_path do
        nil -> ""
        path -> "<span class=\"path-pill\">#{html_escape(path)}</span>"
      end

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Jido Hive Server</title>
        <meta
          name="description"
          content="Jido Hive Server is the API and relay endpoint for the Jido Hive collaboration stack."
        />
        <style>
          :root {
            color-scheme: light;
            --bg: #f4f6f3;
            --bg-grid: rgba(15, 23, 42, 0.055);
            --card: rgba(255, 255, 255, 0.82);
            --card-border: rgba(15, 23, 42, 0.1);
            --ink: #12202f;
            --muted: #5d6876;
            --accent: #0f766e;
            --accent-soft: rgba(15, 118, 110, 0.12);
            --accent-strong: #0b5f59;
            --shadow: 0 24px 60px rgba(15, 23, 42, 0.08);
            --mono: "Berkeley Mono", "JetBrains Mono", "SFMono-Regular", ui-monospace, monospace;
            --sans: "IBM Plex Sans", "Aptos", "Segoe UI", sans-serif;
          }

          * {
            box-sizing: border-box;
          }

          body {
            margin: 0;
            min-height: 100vh;
            font-family: var(--sans);
            color: var(--ink);
            background:
              radial-gradient(circle at top left, rgba(15, 118, 110, 0.12), transparent 32rem),
              radial-gradient(circle at bottom right, rgba(15, 23, 42, 0.08), transparent 30rem),
              linear-gradient(var(--bg-grid) 1px, transparent 1px),
              linear-gradient(90deg, var(--bg-grid) 1px, transparent 1px),
              var(--bg);
            background-size: auto, auto, 2.5rem 2.5rem, 2.5rem 2.5rem, auto;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem;
          }

          main {
            width: min(100%, 70rem);
            background: var(--card);
            border: 1px solid var(--card-border);
            border-radius: 1.75rem;
            box-shadow: var(--shadow);
            backdrop-filter: blur(10px);
            overflow: hidden;
          }

          .hero {
            padding: 3.5rem clamp(1.5rem, 3vw, 3rem) 1.75rem;
            border-bottom: 1px solid rgba(15, 23, 42, 0.08);
          }

          .eyebrow,
          .path-pill {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.45rem 0.8rem;
            border-radius: 999px;
            background: var(--accent-soft);
            color: var(--accent-strong);
            font-family: var(--mono);
            font-size: 0.78rem;
            letter-spacing: 0.03em;
          }

          h1 {
            margin: 1rem 0 0;
            font-size: clamp(2.4rem, 4vw, 4.25rem);
            line-height: 0.95;
            letter-spacing: -0.045em;
          }

          .lede {
            max-width: 44rem;
            margin: 1rem 0 0;
            font-size: 1.04rem;
            line-height: 1.65;
            color: var(--muted);
          }

          .meta {
            display: flex;
            flex-wrap: wrap;
            gap: 0.8rem;
            margin-top: 1.1rem;
          }

          .content {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(18rem, 1fr));
            gap: 1rem;
            padding: clamp(1.25rem, 2vw, 2rem);
          }

          section {
            padding: 1.2rem;
            border-radius: 1.2rem;
            border: 1px solid rgba(15, 23, 42, 0.08);
            background: rgba(255, 255, 255, 0.72);
          }

          h2 {
            margin: 0 0 0.85rem;
            font-size: 0.95rem;
            letter-spacing: 0.02em;
            text-transform: uppercase;
          }

          p {
            margin: 0.4rem 0 0;
            color: var(--muted);
            line-height: 1.55;
          }

          ul {
            margin: 0.75rem 0 0;
            padding-left: 1rem;
            color: var(--muted);
          }

          li + li {
            margin-top: 0.55rem;
          }

          code,
          pre,
          .endpoint {
            font-family: var(--mono);
          }

          .endpoint {
            display: block;
            margin-top: 0.8rem;
            padding: 0.85rem 0.95rem;
            border-radius: 0.95rem;
            background: #e8edeb;
            color: #113238;
            text-decoration: none;
            word-break: break-word;
          }

          pre {
            margin: 0.85rem 0 0;
            padding: 0.95rem;
            overflow-x: auto;
            border-radius: 0.95rem;
            background: #111827;
            color: #d1f3ea;
            font-size: 0.88rem;
            line-height: 1.5;
          }

          a {
            color: var(--accent-strong);
          }

          .footer {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            gap: 0.9rem;
            padding: 0 2rem 2rem;
            color: var(--muted);
            font-size: 0.95rem;
          }

          @media (max-width: 720px) {
            body {
              padding: 1rem;
            }

            .hero {
              padding-top: 2.2rem;
            }

            .footer {
              padding: 0 1.25rem 1.25rem;
            }
          }
        </style>
      </head>
      <body>
        <main>
          <div class="hero">
            <span class="eyebrow">#{status_label}</span>
            <h1>Jido Hive Server</h1>
            <p class="lede">
              #{html_escape(summary)} This service coordinates locked round-robin collaboration rooms
              for 1 to 39 generic workers, exposes the API under <code>/api</code>, and serves the
              relay websocket at <code>/socket/websocket</code>.
            </p>
            <div class="meta">
              #{path_html}
              <span class="path-pill">Host: #{html_escape(display_host(urls.base_url))}</span>
            </div>
          </div>

          <div class="content">
            <section>
              <h2>What This Is</h2>
              <p>
                This root page is for humans. The operational surface of the app is the JSON API and
                websocket relay used by the repo helpers to coordinate generic workers.
              </p>
              <a class="endpoint" href="#{html_escape(urls.api_base)}/targets">GET #{html_escape(urls.api_base)}/targets</a>
              <a class="endpoint" href="#{html_escape(@repo_url)}">Repository: #{html_escape(@repo_url)}</a>
            </section>

            <section>
              <h2>Demo Shape</h2>
              <p>
                The current demo locks the selected worker set at room creation and defaults to
                <code>participant_count * 3</code> planned turns.
              </p>
              <span class="endpoint">API base: #{html_escape(urls.api_base)}</span>
              <span class="endpoint">Websocket: #{html_escape(urls.websocket)}</span>
              <ul>
                <li><code>GET /api/targets</code> lists the currently connected workers.</li>
                <li><code>POST /api/rooms</code> locks the selected worker set into a room execution plan.</li>
                <li><code>POST /api/rooms/:id/run</code> runs the locked plan until the requested completed-turn count is reached.</li>
              </ul>
            </section>

            <section>
              <h2>Local Dev</h2>
              <p>Use one control terminal and one client terminal, or launch workers directly.</p>
              <pre>#{html_escape(local_commands)}</pre>
            </section>

            <section>
              <h2>Run Against Prod</h2>
              <p>The same helpers support the deployed server with explicit <code>--prod</code> flags.</p>
              <pre>#{html_escape(prod_commands)}</pre>
            </section>
          </div>

          <div class="footer">
            <span>Production browser visits land here instead of a raw JSON 404.</span>
            <span>Local scripts stay default-local and opt into prod with <code>--prod</code>.</span>
          </div>
        </main>
      </body>
    </html>
    """
  end

  defp display_host(base_url) do
    case URI.parse(base_url) do
      %URI{host: nil} -> @prod_host
      %URI{host: host} -> host
    end
  end

  defp html_escape(value) do
    value
    |> Plug.HTML.html_escape_to_iodata()
    |> IO.iodata_to_binary()
  end
end
