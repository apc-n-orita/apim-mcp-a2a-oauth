"""MCP ツール: Foundry IQ ナレッジベース検索

Blueprint として定義し、function_app.py 側で register_functions する。
検索そのものは shared/kb_client.py、認可は shared/auth.py が持つ。
このモジュールは「MCP ツールとしての契約」に専念する:
  - ツール定義 (名前・説明・プロパティ)
  - 認可の実行順
  - span 属性
  - MCP クライアントへ返す文言
"""

import logging

import azure.functions as func
from opentelemetry.trace import Status, StatusCode

from shared import kb_client
from shared.auth import (
    REQUIRE_USER_TOKEN,
    check_mcp_invoke_role,
    extract_user_token,
    get_mcp_headers,
)
from shared.telemetry import get_tracer

bp = func.Blueprint()

_logger = logging.getLogger(__name__)
_tracer = get_tracer(__name__)

# mcp_tool はツール名を関数名から決める (tool_name = target_func.__name__)。
# span 名とログの tool フィールドを関数名と一致させるため定数で持つ。
TOOL_NAME = "foundryiq_knowledge_retrieve"


# mcp_tool_property は arg_name をキーに __mcp_tool_properties__ へ追記していくため、
# 引数ごとに重ねて指定できる。
# is_required の既定は True。ドキュメントは「既定は任意」と書いているが
# Python デコレータ側は追随していないため、任意/必須のどちらも明示する。
#
# 引数の並びは funcmcp の (message, ctx) と異なり ctx を先に置いている。
# is_required=False の system_instructions に Python のデフォルト値が必要で、
# デフォルト値付き引数より後ろにデフォルト無しの ctx は置けないため。
# ctx の型注釈は funcmcp と同じく func.MCPToolContext のまま。
# (mcp_tool の wrapper は型注釈で ctx を判別し、引数はすべてキーワードで渡すため
#  並び順は結果に影響しない。)
@bp.mcp_tool()
@bp.mcp_tool_property(
    arg_name="query",
    description=(
        "One complete question in natural language. Keep distinctive tokens verbatim: "
        "proper nouns, acronyms, identifiers, quoted phrases, version strings, and any "
        "date or range constraints. Do not rewrite into keyword search syntax."
    ),
    is_required=True,
)
# system_instructions の効き方はナレッジベース定義の outputMode に依存する。
#   answerSynthesis : 回答生成に効く (引用の付け方、該当なし時の文言など)
#   extractiveData  : 回答生成が無いため、クエリプランニングにしか効かない
# 下の description は answerSynthesis を前提に書いてある。KB 側のモードを
# 切り替えるときは、この文言も合わせて見直すこと。放置するとエージェントが
# 効果のない指示を送り続ける。
@bp.mcp_tool_property(
    arg_name="system_instructions",
    description=(
        "Optional grounding instructions for the retrieval engine, for example how to "
        "cite ref_id values or what to answer when nothing is found. Leave empty to use "
        "the knowledge base defaults."
    ),
    is_required=False,
)
def foundryiq_knowledge_retrieve(
    query: str, ctx: func.MCPToolContext, system_instructions: str = ""
) -> str:
    """Search the Foundry IQ knowledge base for authoritative, source-attributable content.

    Results are trimmed to what the calling user is permitted to see, based on the
    document-level ACL metadata stored in the index. Returns grounding data with ref_id
    values for citation.
    """
    headers = get_mcp_headers(ctx)

    # 認可判定は span の外で行う。トークンの有無や認可の可否は資格情報由来の
    # 情報であり、テレメトリとして外部に送られる span 属性には含めない。
    #
    # 失敗理由も呼び出し元へ返さない。必要なロール名や要求ヘッダー名を返すと、
    # 認可の仕組みを外部に開示することになる。
    # どの段階で落ちたかはログにのみ残し、呼び出し元には一律 "Forbidden" を返す。

    # 1. Function への入口: Easy Auth トークンの App Role
    if not check_mcp_invoke_role(headers.get("x-ms-client-principal", "")):
        _logger.warning("Access denied.", extra={"tool": TOOL_NAME, "stage": "app_role"})
        return "Forbidden"

    # 2. ドキュメントの可視性: ACL 用ユーザートークン
    user_token = extract_user_token(headers)
    if REQUIRE_USER_TOKEN and not user_token:
        _logger.warning("Access denied.", extra={"tool": TOOL_NAME, "stage": "acl_header"})
        return "Forbidden"

    # 設定不足の詳細 (どの環境変数が欠けているか) は呼び出し元へ返さない。
    # サーバー側の構成情報にあたるため、ログにのみ残す。
    if not kb_client.is_configured():
        _logger.error(
            "Missing configuration.",
            extra={"tool": TOOL_NAME, **kb_client.config_state()},
        )
        return "Missing configuration."

    if not query:
        _logger.warning("Empty query.", extra={"tool": TOOL_NAME})
        return "No 'query' provided."

    with _tracer.start_as_current_span(TOOL_NAME) as span:
        # span 属性を立てるのはこの関数に集約する。
        # kb_client.retrieve() にはこの span を明示的に渡し、トークン消費量などを
        # _log_activity から直接この span の属性として記録させる (INFO ログは
        # root logger が既定で WARNING のため配信されず消えるため、ログでは持たない)。
        span.set_attribute("mcp.tool.name", TOOL_NAME)
        span.set_attribute("kb.name", kb_client.KNOWLEDGE_BASE_NAME)

        try:
            text = kb_client.retrieve(query, system_instructions or "", user_token, span)
            span.set_attribute("mcp.tool.success", True)
            if not text:
                span.set_attribute("kb.empty_response", True)
                return "No results."
            return text
        except Exception as e:
            # ACL 評価の失敗 (Graph API 到達不可など) は 5xx で返り、
            # 部分的にフィルタされた結果は返らない (fail-closed)。
            # SDK は HttpResponseError を投げるため、status_code があれば記録する。
            # 接続失敗系の ServiceRequestError は status_code を持たないので
            # getattr でガードする。
            span.set_attribute("mcp.tool.success", False)
            status_code = getattr(e, "status_code", None)
            if status_code is not None:
                span.set_attribute("http.status_code", status_code)
            span.set_attribute("error_type", type(e).__name__)
            # 失敗としてマークするのは span の役割。Failures ブレードと失敗率がこれを見る。
            # 例外の詳細は _logger.exception 側に集約し、record_exception は使わない。
            # 併用すると exceptions テーブルに二重計上され、しかも record_exception 側は
            # サンプリングで落ちうるため、信頼できるのはログ側になる。
            span.set_status(Status(StatusCode.ERROR, type(e).__name__))

            # span はサンプリングで落ちうるため、調査に必要な情報はすべてログ側に持たせる。
            # exception() はスタックトレースを含めて記録する。
            _logger.exception(
                "Knowledge retrieval failed.",
                extra={
                    "tool": TOOL_NAME,
                    "error_type": type(e).__name__,
                    "status_code": status_code,
                    "reason": getattr(e, "reason", None),
                    "kb": kb_client.KNOWLEDGE_BASE_NAME,
                    "api_version": kb_client.SEARCH_API_VERSION,
                    "acl_header_present": bool(user_token),
                },
            )
            # 例外の内容は呼び出し元へ返さない。検索サービスのエラー本文には
            # エンドポイントやインデックス名などの内部情報が含まれうるため、
            # 詳細はログと span にのみ残し、呼び出し元には固定メッセージを返す。
            return "Knowledge retrieval failed"
