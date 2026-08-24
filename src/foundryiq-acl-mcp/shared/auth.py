"""MCP ツールの認可に関する処理

2 段の認可を扱う。

  1. Function への入口   : Easy Auth が発行したトークンの Mcp.Invoke ロール
  2. ドキュメントの可視性 : x-ms-query-source-authorization ヘッダーのユーザー識別

1 は Function の App ID を audience とし、
2 は https://search.azure.com/.default スコープのトークンを使う。
audience が異なるため、クライアントは 2 本のトークンを取得して送る必要がある。

トークンに関わる判定はトレース対象に含めない。span 属性はテレメトリとして
外部に送られるため、認可の可否やトークンの有無といった資格情報由来の情報は
logger のみに残す。失敗時だけ記録し、成功時は何も出さない。

環境変数:
  MCP_REQUIRE_USER_TOKEN  既定 true。false にすると ACL ヘッダー無しでも実行する
"""

import base64
import json
import logging
import os

import azure.functions as func

_logger = logging.getLogger(__name__)

ACL_HEADER = "x-ms-query-source-authorization"
REQUIRE_USER_TOKEN = os.getenv("MCP_REQUIRE_USER_TOKEN", "true").lower() != "false"


def get_mcp_headers(ctx: func.MCPToolContext) -> dict:
    """MCP トランスポートが受け取った HTTP ヘッダーを小文字キーで返す

    MCPToolContext は dict のサブクラス。mcp_tool デコレータが
    json.loads(context) の結果をそのまま渡すため、辞書として扱える。
    """
    raw: dict = ctx.get("transport", {}).get("properties", {}).get("headers", {})
    return {k.lower(): v for k, v in raw.items()}


def check_mcp_invoke_role(principal_header: str) -> bool:
    """Easy Auth の x-ms-client-principal に Mcp.Invoke ロールが含まれるか検証する

    Reference: https://learn.microsoft.com/azure/app-service/configure-authentication-user-identities
    """
    if not principal_header:
        _logger.warning("Mcp.Invoke role check failed.", extra={"reason": "header_missing"})
        return False
    try:
        principal = json.loads(base64.b64decode(principal_header).decode("utf-8"))
        if any(
            c.get("typ") == "roles" and c.get("val") == "Mcp.Invoke"
            for c in principal.get("claims", [])
        ):
            return True
        _logger.warning("Mcp.Invoke role check failed.", extra={"reason": "role_not_found"})
        return False
    except Exception as e:
        _logger.warning(
            "Mcp.Invoke role check failed.",
            extra={"reason": "decode_error", "error.type": type(e).__name__},
        )
        return False


def extract_user_token(headers: dict) -> str:
    """ACL 用のユーザートークンを取り出す

    クライアントは x-ms-query-source-authorization に search.azure.com スコープの
    トークンを入れて送る。"Bearer " 接頭辞は付いていても付いていなくても受け付ける
    (SDK は生のトークン文字列を期待する)。
    """
    raw = headers.get(ACL_HEADER, "") or ""
    if raw.lower().startswith("bearer "):
        return raw[7:].strip()
    return raw.strip()
