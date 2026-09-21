///|
priv enum Block {
  Paragraph(String)
  Code(String, String)
  Items(Array[String])
  Links(Array[(String, String)])
  Endpoints
}

///|
priv struct Section {
  id : String
  title : String
  blocks : Array[Block]
}

///|
fn t(locale : @site.Locale, en : String, ja : String) -> String {
  if locale == @site.Japanese {
    ja
  } else {
    en
  }
}

///|
fn description(locale : @site.Locale) -> String {
  t(
    locale, "Turn editable Poietra projects into SVG, PNG and MP4. Connect your agent through OpenAPI or a local MCP server.",
    "編集できる Poietra のプロジェクトを SVG・PNG・MP4 へ。OpenAPI とローカル MCP から、エージェントを制作につなぎます。",
  )
}

///|
let setup : String =
  #|git clone https://github.com/Poietra/poietra.git
  #|cd poietra
  #|pnpm install --frozen-lockfile
  #|curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/install-moonbit.sh
  #|bash /tmp/install-moonbit.sh "$(cat .moon-version)"
  #|export PATH="$HOME/.moon/bin:$PATH"
  #|node scripts/moon.mjs update
  #|pnpm build:moonbit
  #|pnpm render:api

///|
let render_example : String =
  #|curl -fsS https://poietra.com/examples/hello.poietra.json -o hello.poietra.json
  #|curl -fsS http://127.0.0.1:8799/inspect \
  #|  -H 'Content-Type: application/json' \
  #|  --data-binary @hello.poietra.json
  #|curl -fsS 'http://127.0.0.1:8799/render?format=mp4&width=1280&fps=30' \
  #|  -H 'Content-Type: application/json' \
  #|  --data-binary @hello.poietra.json \
  #|  -o hello.mp4

///|
fn mcp_config() -> String {
  let value : Json = {
    "mcpServers": {
      "poietra": {
        "command": "node",
        "args": ["/absolute/path/to/poietra/apps/render/mcp.mjs"],
      },
    },
  }
  value.stringify(indent=2)
}

///|
fn sections(locale : @site.Locale) -> Array[Section] {
  [
    {
      id: "quickstart",
      title: t(
        locale, "Start the render service", "描画サービスを起動する",
      ),
      blocks: [
        Paragraph(
          t(
            locale, "Use Node 24+, pnpm 10.23.0 and Python 3.12+. These POSIX shell commands install the pinned MoonBit compiler and build the renderer. Runtime rendering does not need Chromium, FFmpeg or an OpenAI key.",
            "Node 24 以降、pnpm 10.23.0、Python 3.12 以降を用意します。以下は POSIX シェル用で、固定したバージョンの MoonBit を導入し、描画エンジンをビルドします。描画時に Chromium・FFmpeg・OpenAI キーは不要です。",
          ),
        ),
        Code("sh", setup),
        Paragraph(
          t(
            locale, "Keep that process running. In another terminal, inspect and render the sample below. The file contains one second of editable text.",
            "起動したプロセスを残し、別のターミナルでサンプルを検査・描画します。サンプルには、編集できる１秒間のテキストが入っています。",
          ),
        ),
        Code("sh", render_example),
        Links([("hello.poietra.json", "/examples/hello.poietra.json")]),
      ],
    },
    {
      id: "http",
      title: "HTTP / OpenAPI",
      blocks: [
        Paragraph(
          t(
            locale, "Send the complete .poietra.json file directly as the application/json body. Output settings go in the query string. A successful render returns the actual file bytes with the matching Content-Type.",
            ".poietra.json 全体を application/json の本文として送ります。出力条件はクエリに指定します。描画が成功すると、適切な Content-Type と実際のファイル本体が返ります。",
          ),
        ),
        Endpoints,
        Code(
          "text", "format=svg|png|mp4\nwidth=1280&height=720\nfps=24|30|60\ntimeMs=1200",
        ),
        Paragraph(
          t(
            locale, "The default format is PNG. timeMs selects a still frame and must be zero for MP4. One supplied dimension preserves the first Scene's aspect ratio. MP4 requires even dimensions.",
            "既定の形式は PNG です。timeMs は静止フレームの時刻で、MP4 では 0 にします。幅・高さの片方だけを指定すると、最初の Scene の縦横比を保ちます。MP4 の寸法は偶数が必要です。",
          ),
        ),
        Links([
          ("OpenAPI 3.1.1", "/openapi.json"),
          ("Project JSON Schema", "/schemas/project.json"),
        ]),
        Paragraph(
          t(
            locale, "The downloadable OpenAPI targets http://127.0.0.1:8799. Your running server also exposes /openapi.json with its actual origin. A public poietra.com URL is not a render server.",
            "ダウンロードする OpenAPI の接続先は http://127.0.0.1:8799 です。起動したサーバー自身の /openapi.json には、その実際の接続先が入ります。poietra.com の公開 URL は描画サーバーではありません。",
          ),
        ),
      ],
    },
    {
      id: "mcp",
      title: t(
        locale, "Connect a local MCP client", "ローカル MCP を接続する",
      ),
      blocks: [
        Paragraph(
          t(
            locale, "After building, let your MCP client launch apps/render/mcp.mjs over stdio. This is an example for clients with an mcpServers configuration. Replace the absolute path and adapt the surrounding configuration to your client. The HTTP server does not need to be running.",
            "ビルド後、MCP クライアントから apps/render/mcp.mjs を stdio で起動します。以下は mcpServers 形式の設定例です。絶対パスを置き換え、クライアントの設定形式に合わせてください。HTTP サーバーの起動は不要です。",
          ),
        ),
        Code("json", mcp_config()),
        Links([
          (
            t(
              locale, "Download example configuration", "設定例をダウンロード",
            ),
            "/developers/mcp-config.json",
          ),
        ]),
        Items([
          "poietra_capabilities — " +
          t(
            locale, "Read formats, source types and limits.", "対応形式・素材・上限を確認。",
          ),
          "poietra_inspect — " +
          t(
            locale, "Inspect a local inputPath.", "ローカルの inputPath を検査。",
          ),
          "poietra_render — " +
          t(
            locale, "Render inputPath to a new outputPath. Existing files are never overwritten.",
            "inputPath を描画して新しい outputPath に保存。既存ファイルは上書きしません。",
          ),
        ]),
        Code(
          "json", "{\n  \"inputPath\": \"/absolute/path/to/hello.poietra.json\",\n  \"outputPath\": \"/absolute/path/to/hello.mp4\",\n  \"format\": \"mp4\",\n  \"fps\": 30\n}",
        ),
        Paragraph(
          t(
            locale, "Use MCP resources/list and resources/read to retrieve the same specification, project schema and starter file. Paths refer to the machine running the MCP process. There is currently no remote /mcp endpoint.",
            "MCP の resources/list・resources/read からも、同じ仕様・プロジェクトスキーマ・サンプルを取得できます。ファイルパスは MCP プロセスが動く端末のものです。現在、リモートの /mcp エンドポイントはありません。",
          ),
        ),
        Code(
          "text", "poietra://docs/openapi\npoietra://docs/project-schema\npoietra://examples/hello",
        ),
      ],
    },
    {
      id: "workflow",
      title: t(
        locale, "Keep the project editable", "編集できる構造を保つ",
      ),
      blocks: [
        Paragraph(
          t(
            locale, "An agent edits the project data, inspects it, then renders it. Keep stable object IDs. A Scene holds shared object identities and parent links; each Composition holds its own appearance and transforms. Transitions connect adjacent Compositions and contain timing, easing and intermediate values.",
            "エージェントはプロジェクトのデータを編集し、検査してから描画します。オブジェクト ID は保ちます。Scene は共通の識別子と親子関係、Composition はそれぞれの見た目と変形を持ち、隣接する Composition を結ぶ Transition に時間・イージング・中間値を保存します。",
          ),
        ),
        Paragraph(
          t(
            locale, "The project schema is generated from the file decoder. Inspection additionally checks references and timing. An empty issues array is a compatibility preflight, not proof that every embedded asset can decode. Correct reported errors before retrying a render.",
            "プロジェクトスキーマはファイルの検証定義から生成しています。検査では参照関係や時間も確認します。issues が空でも、埋め込んだ全素材の復号成功を保証するものではありません。描画時のエラーは内容を修正してから再試行します。",
          ),
        ),
        Links([
          (
            t(
              locale, "Source and extension guide", "ソースと拡張ガイド",
            ),
            "https://github.com/Poietra/poietra#add-a-feature",
          ),
        ]),
      ],
    },
    {
      id: "limits",
      title: t(locale, "Formats and limits", "対応形式と上限"),
      blocks: [
        Items([
          t(
            locale, "Output: SVG, PNG and H.264 MP4; audio uses MP3 inside MP4.",
            "出力：SVG・PNG・H.264 MP4。MP4 内の音声は MP3。",
          ),
          t(
            locale, "Input media: embedded PNG/JPEG and PCM WAV. Imported video, WebP, compressed audio and external asset URLs are unsupported.",
            "入力素材：埋め込み PNG/JPEG と PCM WAV。動画・WebP・圧縮音声・外部の素材 URL は未対応。",
          ),
          t(
            locale, "Input ≤ 32 MiB; output ≤ 64 MiB. Each side ≤ 1920 px; total ≤ 2,073,600 pixels.",
            "入力 32 MiB 以下、出力 64 MiB 以下。各辺 1920 px 以下、合計 2,073,600 ピクセル以下。",
          ),
          t(
            locale, "MP4: up to 60 seconds and 1800 frames. At most 32 audible tracks.",
            "MP4：60 秒以内かつ 1800 フレーム以内。音が出るトラックは最大 32 本。",
          ),
          t(
            locale, "One HTTP inspection/render at a time. Requests wait for completion; there is no job queue, job ID or hosted result storage.",
            "HTTP の検査・描画は一度に１件。完了まで応答を待ちます。ジョブキュー・ジョブ ID・結果のホスト保存はありません。",
          ),
          t(
            locale, "Default render timeout: 120 seconds. Disconnecting HTTP or cancelling MCP stops the job.",
            "描画の既定タイムアウトは 120 秒。HTTP の切断や MCP のキャンセルで処理を中断します。",
          ),
        ]),
      ],
    },
    {
      id: "auth",
      title: t(locale, "Authentication and errors", "認証とエラー"),
      blocks: [
        Paragraph(
          t(
            locale, "The service listens on loopback by default. Configure POIETRA_RENDER_TOKEN before binding to another interface, and send Authorization: Bearer <token>. A configured token is also required on loopback. These credentials are separate from studio login.",
            "既定ではループバックで待ち受けます。他のインターフェースで公開する場合は POIETRA_RENDER_TOKEN を設定し、Authorization: Bearer <token> を送ります。トークンを設定した場合はローカルでも必須です。Studio のログインとは別の認証です。",
          ),
        ),
        Items([
          "400 — " +
          t(
            locale, "Unknown or repeated query options.", "未知・重複した出力条件。",
          ),
          "401 / 403 — " +
          t(
            locale, "Authentication, Origin or Host rejected.", "認証・Origin・Host の拒否。",
          ),
          "413 / 415 — " +
          t(
            locale, "Input too large or wrong Content-Type.", "入力サイズ超過・Content-Type の不一致。",
          ),
          "422 — " +
          t(
            locale, "Invalid data, unsupported media or rendering failure. Read the error message.",
            "データ不正・未対応素材・描画失敗。error の内容を確認。",
          ),
          "429 — " +
          t(
            locale, "Busy. Retry after the current operation finishes.", "処理中。先行する処理の完了後に再試行。",
          ),
          "504 — " +
          t(
            locale, "Render timeout. Reduce the workload before retrying.", "描画タイムアウト。負荷を減らしてから再試行。",
          ),
        ]),
        Code("json", "{\"error\":\"format must be svg, png or mp4.\"}"),
      ],
    },
  ]
}
