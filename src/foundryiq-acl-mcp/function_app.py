"""Foundry IQ ナレッジベース検索を提供する Function MCP サーバー (エントリポイント)

このファイルはテレメトリの初期化と Blueprint の登録のみを行う。
ツールの実装は tools/ 以下、共通処理は shared/ 以下に置く。

  function_app.py            登録のみ
  tools/knowledge_retrieve.py  MCP ツール (Blueprint)
  shared/telemetry.py          OpenTelemetry / Application Insights の初期化
  shared/auth.py               Easy Auth の App Role 検証と ACL トークン取り出し
  shared/kb_client.py          ナレッジベース検索 (azure-search-documents)

MCP ツールを追加するときは tools/ に Blueprint を持つモジュールを作り、
ここで register_functions を 1 行足す。

参照した既存実装:
  - apim-mcp-oauth/src/funcmcp/function_app.py
      MCP ツールの定義方法 (@app.mcp_tool / @app.mcp_tool_property)、
      Easy Auth の x-ms-client-principal による App Role 検証、
      MCPToolContext からのヘッダー取得、OpenTelemetry の span 構成。
  - msfoundry-docsacl-apim/appcodes/acl_on/modules/response_api.py
      x-ms-query-source-authorization にユーザートークンを載せる方式。
      ただし当該実装は Responses API 経由 + OBO 交換であり、本モジュールは
      SDK の retrieve を直接呼び、OBO を行わない点が異なる。

環境変数:
  SEARCH_ENDPOINT                       https://<service>.search.windows.net
  KNOWLEDGE_BASE_NAME                   ナレッジベース名
  SEARCH_API_VERSION                    既定 2026-05-01-preview
  MCP_REQUIRE_USER_TOKEN                既定 true。false にすると ACL ヘッダー無しでも実行する
  APPLICATIONINSIGHTS_CONNECTION_STRING OpenTelemetry 送信先
"""

import azure.functions as func
from dotenv import load_dotenv

load_dotenv(override=False)

# Blueprint を import する前にテレメトリを初期化する。
# 各モジュールが import 時に logger / tracer を取得するため順序が要る。
from shared.telemetry import configure  # noqa: E402

configure()

from tools.knowledge_retrieve import bp as knowledge_retrieve_bp  # noqa: E402

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)
app.register_functions(knowledge_retrieve_bp)
