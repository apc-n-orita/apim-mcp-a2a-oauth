"""Foundry IQ ナレッジベースの検索 (OBO なし / Python SDK 使用)

使用する SDK:
  azure-search-documents の KnowledgeBaseRetrievalClient。
  retrieve() が query_source_authorization パラメータを持つため、
  ACL ヘッダーを自前で組み立てる必要がない。

  プレリリース版 (12.1.0b1) が必須。安定版 12.0.0 との差:
    12.0.0   : query_source_authorization が存在せず、渡しても **kwargs に
               吸われて無視される。api_version 既定は 2026-04-01。
    12.1.0b1 : query_source_authorization あり。api_version 既定は
               2026-05-01-preview。

    pip install azure-search-documents==12.1.0b1

  なお SearchClient 側には旧名 x_ms_query_source_authorization の互換処理が
  あるが、KnowledgeBaseRetrievalClient.retrieve() には無い。

  参考:
    https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-retrieve
    https://learn.microsoft.com/python/api/azure-search-documents/azure.search.documents.knowledgebases.knowledgebaseretrievalclient

設計 (OBO を使わない理由と成立条件):
  Azure AI Search の query-time ACL は、1 リクエストに 2 つの独立した認可情報を
  求める。両方が必要で、片方が他方を代替しない。

    credential (Authorization)      : 呼び出しアプリの RBAC (Search Index Data Reader)
    query_source_authorization      : 結果を絞り込む対象ユーザーの識別
                                      (SDK 内部で x-ms-query-source-authorization ヘッダーになる)

  後者は検索サービスへの権限を必要とせず、トークンから oid とグループクレームを
  読むためだけに使われる。audience が https://search.azure.com であればよく、
  Fabric Data Agent / Fabric Ontology / Work IQ 以外のナレッジソースでは
  検索エンジン側でのトークン交換 (OBO) は発生しない。
  よってクライアントが search スコープのトークンを直接渡せば OBO は不要。

  公式ドキュメントの SDK 例も、サービス資格情報とユーザートークンを
  別引数で渡すだけで交換していない。

  参考:
    https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement

前提条件:
  - Function のマネージド ID に検索サービスの Search Index Data Reader ロール
  - ナレッジソースを ingestionPermissionOptions 付きで作成済みであること
      未設定だとインデックスに権限メタデータが無い。2026-05-01-preview では
      ユーザートークンを渡しても ACL 保護コンテンツが返らない (fail-closed) ため、
      「何も返ってこない」形で失敗する。
  - userIds / groupIds は UPN やメールではなく Entra オブジェクト ID (GUID)

タイムアウト:
  azure-core の既定は接続 300 秒 / 読み取り 300 秒、リトライ 10 回。
  この既定のままだと、Search がハングしたときに SDK が諦めるより先に
  Functions の functionTimeout が来る。その間 invocation はワーカーの
  同時実行スロットを占有し続け、正常なリクエストまで待たされる。
  MCP ツールの呼び出し元はエージェントで、待つ以外の選択肢を持たないため、
  サーバー側で短く切って明示的にエラーを返す。

  50 秒は answerSynthesis 有効時に LLM 呼び出しが挟まることを見込んだ暫定値。
  所要時間の実測は span (dependencies テーブル) の duration を見る。
  _log_activity はトークンと部分失敗のみで、所要時間は出していない。

  二段構えにしている。
    SEARCH_MAX_RUNTIME (50) : Search 側が先に切り上げ、正規のレスポンスを返す
    SEARCH_READ_TIMEOUT (60): サーバーが応答すらしない異常時の最後の砦
  前者を短くしておかないと、常にソケット切断が先に起きて activity ログを失う。

    リトライは行わない。Search 側の失敗を再試行すると MCP クライアントの
    100 秒タイムアウトを超えるため、初回のエラーを呼び出し元へ返す。

環境変数:
  SEARCH_ENDPOINT         https://<service>.search.windows.net
  KNOWLEDGE_BASE_NAME     ナレッジベース名
  SEARCH_API_VERSION      既定 2026-05-01-preview
  SEARCH_CONNECT_TIMEOUT  既定 10 秒
  SEARCH_READ_TIMEOUT     既定 60 秒
    SEARCH_RETRY_TOTAL      既定 0 回
  SEARCH_MAX_RUNTIME      既定 50 秒 (サーバー側の実行時間上限)
  SEARCH_MAX_OUTPUT_DOCUMENTS 既定 10 (grounding data に含める上限ドキュメント数)
  SEARCH_MAX_OUTPUT_SIZE      既定 6000 (grounding data の上限文字数)
  SEARCH_RETRIEVAL_REASONING_EFFORT 既定 "low"。"minimal" / "low" / "medium" のいずれか。
      minimal : ソース選択・クエリプランニング・反復検索を一切行わない
                (reasoning_tokens を最小に抑えられるが再現率も下がる)
      low     : 軽い reasoning (既定)
      medium  : SDK が本来既定として想定する reasoning。reasoning_tokens が増える
    参考: https://learn.microsoft.com/azure/search/agentic-retrieval-overview#availability-and-pricing
"""

import logging
import os

from azure.identity import DefaultAzureCredential
from azure.search.documents.knowledgebases import KnowledgeBaseRetrievalClient
from azure.search.documents.knowledgebases.models import (
    KnowledgeBaseRetrievalRequest,
    KnowledgeRetrievalLowReasoningEffort,
    KnowledgeRetrievalMediumReasoningEffort,
    KnowledgeRetrievalMinimalReasoningEffort,
    KnowledgeRetrievalOutputMode,
    KnowledgeRetrievalSemanticIntent,
)

_logger = logging.getLogger(__name__)

SEARCH_ENDPOINT = os.getenv("SEARCH_ENDPOINT", "").rstrip("/")
KNOWLEDGE_BASE_NAME = os.getenv("KNOWLEDGE_BASE_NAME", "")
SEARCH_API_VERSION = os.getenv("SEARCH_API_VERSION", "2026-05-01-preview")

# azure-core の既定 (接続 300 / 読み取り 300 / リトライ 10) を上書きする。
# 値は retrieve() 呼び出し時にキーワード引数として渡す。クライアント生成時に
# 渡しても効くが、呼び出し側で明示したほうが「どの操作に効く値か」が読める。
SEARCH_CONNECT_TIMEOUT = float(os.getenv("SEARCH_CONNECT_TIMEOUT", "10"))
SEARCH_READ_TIMEOUT = float(os.getenv("SEARCH_READ_TIMEOUT", "60"))
SEARCH_RETRY_TOTAL = int(os.getenv("SEARCH_RETRY_TOTAL", "0"))

# サーバー側の実行時間上限。SEARCH_READ_TIMEOUT より短くすること。
# 先に Search 側が切り上げれば正規のレスポンスが返り、activity ログから
# どこで時間を使ったかを追える。クライアント側タイムアウトはソケットを
# 切るだけなので、応答本文も activity も失われる。
SEARCH_MAX_RUNTIME = int(os.getenv("SEARCH_MAX_RUNTIME", "50"))

# retrieve() の応答に含める grounding data の上限。
# max_output_documents はドキュメント (チャンク) 件数、max_output_size は
# 応答全体の文字数上限。大きくすると呼び出しトークン (answer synthesis /
# MCP 呼び出し元) が増えるため、既定値は SDK 側の推奨値に合わせている。
SEARCH_MAX_OUTPUT_DOCUMENTS = int(os.getenv("SEARCH_MAX_OUTPUT_DOCUMENTS", "10"))
SEARCH_MAX_OUTPUT_SIZE = int(os.getenv("SEARCH_MAX_OUTPUT_SIZE", "6000"))

# retrieval の reasoning effort (Azure AI Search 側の課金・reasoning_tokens に影響)。
# キーは SDK の discriminator 値 ("minimal"/"low"/"medium") と揃える。
# 既定を "low" にしているのは、SDK/サーバー既定の "medium" だと
# reasoning_tokens が数万単位になり課金・レイテンシへの影響が大きいため。
_REASONING_EFFORT_CLASSES = {
    "minimal": KnowledgeRetrievalMinimalReasoningEffort,
    "low": KnowledgeRetrievalLowReasoningEffort,
    "medium": KnowledgeRetrievalMediumReasoningEffort,
}
SEARCH_RETRIEVAL_REASONING_EFFORT = os.getenv("SEARCH_RETRIEVAL_REASONING_EFFORT", "low").strip().lower()
if SEARCH_RETRIEVAL_REASONING_EFFORT not in _REASONING_EFFORT_CLASSES:
    raise ValueError(
        "SEARCH_RETRIEVAL_REASONING_EFFORT must be one of "
        f"{sorted(_REASONING_EFFORT_CLASSES)}, got {SEARCH_RETRIEVAL_REASONING_EFFORT!r}"
    )

# サービス資格情報とクライアントはモジュールスコープで保持する。
# azure-identity 側でトークンをキャッシュするため、呼び出しごとの生成は避ける。
_credential = DefaultAzureCredential()

# ナレッジベース名ごとにクライアントをキャッシュする。
# 将来 1 つの Function で複数のナレッジベースを扱う場合に備えた形。
_clients: dict = {}


def is_configured() -> bool:
    """検索に必要な設定が揃っているか"""
    return bool(SEARCH_ENDPOINT and KNOWLEDGE_BASE_NAME)


def config_state() -> dict:
    """設定の充足状況 (値そのものは含めない)

    ログ用。どの設定が欠けているかは呼び出し元へ返さず、ここに残す。
    """
    return {
        "search_endpoint_set": bool(SEARCH_ENDPOINT),
        "knowledge_base_name_set": bool(KNOWLEDGE_BASE_NAME),
    }


def _get_client(kb_name: str) -> KnowledgeBaseRetrievalClient:
    """KnowledgeBaseRetrievalClient を遅延生成してキャッシュする

    credential は Function のマネージド ID。これが Authorization ヘッダーになり、
    Search Index Data Reader ロールの評価対象となる。

    api_version は 12.1.0b1 の既定と同じ値だが、明示しておく。
    SDK のバージョンを上げたときに既定が変わっても挙動が動かないようにするため。
    """
    if kb_name not in _clients:
        _clients[kb_name] = KnowledgeBaseRetrievalClient(
            endpoint=SEARCH_ENDPOINT,
            knowledge_base_name=kb_name,
            credential=_credential,
            api_version=SEARCH_API_VERSION,
        )
    return _clients[kb_name]


def _build_request(query: str) -> KnowledgeBaseRetrievalRequest:
    """retrieve のリクエストを組み立てる

    intent はクエリをモデルによる分解なしで検索エンジンへ渡す。

    knowledge_source_params は指定しない。ナレッジソースの絞り込みは
    ナレッジベース定義側の責務であり、こちらで指定するとソース種別ごとに
    異なるパラメータクラス (SearchIndex / Web / AzureBlob / RemoteSharePoint など)
    を選ぶ必要が生じ、種別を取り違えると実行時に失敗する。

    output_mode は extractiveData に固定する。MCP 呼び出し側が grounding data を
    使って回答を構成するため、Knowledge Base 側では回答合成を行わない。

    逆に include_activity と max_runtime_in_seconds はここでしか指定できない。
    2026-05-01-preview で、前者は outputConfiguration から、後者は requestLimits
    から、それぞれリクエストオブジェクト側へ移動した。ナレッジベース定義側に
    設定項目が無いため、指定しなければサーバー既定のままになる。
    参考: https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-migrate

    retrieval_reasoning_effort も常に明示する。省略するとサーバー既定 (medium相当)
    になり、agentic reasoning の reasoning_tokens (Azure AI Search 側の課金) が
    増えるため、SEARCH_RETRIEVAL_REASONING_EFFORT (既定 low) を毎回指定する。
    """
    return KnowledgeBaseRetrievalRequest(
        intents=[KnowledgeRetrievalSemanticIntent(search=query)],
        output_mode=KnowledgeRetrievalOutputMode.EXTRACTIVE_DATA,
        max_output_documents=SEARCH_MAX_OUTPUT_DOCUMENTS,
        max_output_size=SEARCH_MAX_OUTPUT_SIZE,
        retrieval_reasoning_effort=_REASONING_EFFORT_CLASSES[SEARCH_RETRIEVAL_REASONING_EFFORT](),
        # activity 配列が無いとトークン消費も 206 部分失敗も追跡できなくなる。
        # サーバー既定に依存させず、常に要求する。
        include_activity=True,
        max_runtime_in_seconds=SEARCH_MAX_RUNTIME,
    )


def _extract_response_text(result) -> str:
    """retrieve のレスポンスから grounding データ文字列を取り出す

    response[].content[].text は ref_id 付きのチャンクを JSON エンコードした文字列。
    extractiveData では、MCP 呼び出し側が回答を構成するための grounding data が入る。
    """
    parts = []
    for message in getattr(result, "response", None) or []:
        for content in getattr(message, "content", None) or []:
            text = getattr(content, "text", None)
            if text:
                parts.append(text)
    return "\n".join(parts)


def _log_activity(result, kb_name: str, span) -> None:
    """activity 配列からトークン消費、ソース単位のエラー/警告を記録する

    ナレッジベース経路は AI Search のリソースログに何も残らないため、
    ここで拾わないとトークン消費 (課金) も部分失敗も後から追跡できない。

    トークン消費・activity/reference件数は、ログではなく呼び出し元
    (tools/knowledge_retrieve.py) から渡された span の属性として記録する。
    configure_azure_monitor() はハンドラを root logger に付けるだけで、
    ログレベル自体は Python の既定値 (WARNING) のまま変えないため、
    _logger.info(...) はハンドラに届く前に握り潰され、Application Insights に
    一切送信されない (samplecodes/foundryiq_acl_local での実行で確認済み)。
    span 属性はログレベルに影響されず、dependencies テーブルの
    customDimensions として確実に届く。
    部分失敗の警告 (下記の _logger.warning) は WARNING レベルなので影響を受けず、
    従来通りログのままにしている。

    activity のレコードはソース種別ごとに別クラスで、持つフィールドが異なる。
      KnowledgeBaseModelQueryPlanningActivityRecord    : input_tokens / output_tokens / model_name
      KnowledgeBaseModelAnswerSynthesisActivityRecord  : input_tokens / output_tokens / model_name
      KnowledgeBaseModelWebSummarizationActivityRecord : input_tokens_count / output_tokens_count
      KnowledgeBaseAgenticReasoningActivityRecord      : reasoning_tokens
      各ソース別レコード (SearchIndex / AzureBlob / Web など) : elapsed_ms と検索引数
    共通の基底クラスが id / type / elapsed_ms / error / warning を持つ。
    種別を網羅せず getattr で拾うことで、SDK のバージョン差に耐える。

    ただし getattr はフィールド名の揺れまでは吸収しない。modelWebSummarization
    だけ Python 属性名が *_tokens_count で、input_tokens しか見ないとエラーも
    警告も出ないまま合計だけが過少になる。両方の名前を見ること。
    なお JSON のワイヤ名は全種別とも inputTokens / outputTokens で共通のため、
    生レスポンスを見ても差異に気づけない。SDK 側の命名揺れである点に注意。

    トークンは請求先が 2 系統に分かれるので、合計を分けて出す。
      Azure OpenAI 側 : query planning / answer synthesis / web summarization の
                        input_tokens / output_tokens
      Azure AI Search 側 : agenticReasoning の reasoning_tokens
                        (単価が retrieval reasoning effort で変わる)
    単価も課金先リソースも違うため、1 つの total にまとめない。
    参考: https://learn.microsoft.com/azure/search/agentic-retrieval-overview#availability-and-pricing

    elapsed_ms は記録しない。サブクエリが並列実行されるため単純合計は実時間と
    一致せず、所要時間は span の duration を見れば足りる。
    """
    activity = getattr(result, "activity", None) or []

    total_input = 0
    total_output = 0
    total_reasoning = 0

    for entry in activity:
        # *_tokens_count は modelWebSummarization の名前。他の種別は *_tokens。
        # 同じレコードが両方を持つことはないため or で繋いでよい。
        total_input += (
            getattr(entry, "input_tokens", None) or getattr(entry, "input_tokens_count", None) or 0
        )
        total_output += (
            getattr(entry, "output_tokens", None)
            or getattr(entry, "output_tokens_count", None)
            or 0
        )
        total_reasoning += getattr(entry, "reasoning_tokens", None) or 0

        # ソース単位の失敗は例外にならず 206 Partial Content で返るため、
        # ここで拾わないと「一部のナレッジソースだけ落ちている」状態に気づけない。
        error = getattr(entry, "error", None)
        warning = getattr(entry, "warning", None)
        if error is not None or warning:
            _logger.warning(
                "Knowledge base activity reported a problem.",
                extra={
                    "kb": kb_name,
                    # type は基底クラスの discriminator。"searchIndex" / "web" /
                    # "modelQueryPlanning" など API 契約側の値なので、SDK の
                    # クラス名より安定し、生 JSON との突き合わせもしやすい。
                    "activity_kind": getattr(entry, "type", None),
                    "activity_id": getattr(entry, "id", None),
                    "activity_error": str(error) if error is not None else None,
                    "activity_warning": warning,
                },
            )

    references = getattr(result, "references", None)

    span.set_attribute("kb.name", kb_name)
    span.set_attribute("kb.api_version", SEARCH_API_VERSION)
    span.set_attribute("kb.activity_count", len(activity))
    span.set_attribute("kb.reference_count", len(references) if references is not None else -1)
    # Azure OpenAI 側に請求される LLM トークン
    span.set_attribute("kb.llm_input_tokens", total_input)
    span.set_attribute("kb.llm_output_tokens", total_output)
    span.set_attribute("kb.llm_total_tokens", total_input + total_output)
    # Azure AI Search 側に請求される検索トークン。単価が異なるため llm_total_tokens には含めない。
    span.set_attribute("kb.reasoning_tokens", total_reasoning)


def retrieve(
    query: str,
    user_token: str,
    span,
    kb_name: str = "",
) -> str:
    """ナレッジベースの retrieve を SDK 経由で呼び、grounding データを返す

    2 つの認可情報を別々に渡すのが本モジュールの要点:
      credential                   -> Function の MI (サービス認証)
      query_source_authorization   -> クライアントから受け取ったユーザートークン

    span は呼び出し元 (tools/knowledge_retrieve.py が
    _tracer.start_as_current_span() で開いたもの) から明示的に受け取り、
    _log_activity にそのまま引き継ぐ。trace.get_current_span() のような
    contextvar 経由の暗黙参照はしない (呼び出し元を跨いだ受け渡しを明示するため)。
    結果が無い場合は空文字を返し、呼び出し元の応答文言はここでは決めない。
    """
    kb_name = kb_name or KNOWLEDGE_BASE_NAME
    request = _build_request(query)

    # パラメータ名は query_source_authorization (x_ms_ 接頭辞は付かない)。
    # SDK 内部で x-ms-query-source-authorization ヘッダーに変換される。
    # 誤った名前を渡しても **kwargs に吸われて黙って無視されるため、
    # ACL が効かないまま動いてしまう。名前を変えないこと。
    #
    # user_token が空のときは None を渡す。
    # 2026-05-01-preview 以降、トークン省略時は ACL 保護コンテンツが返らない
    # (fail-closed)。空文字を渡すと不正なヘッダーになるため区別する。
    # タイムアウトとリトライ回数は **kwargs 経由で azure-core のパイプラインに渡る。
    # 打ち切られた場合は ServiceRequestError / ServiceResponseError が上がり、
    # 呼び出し元の except で拾われる (status_code は持たない)。
    result = _get_client(kb_name).retrieve(
        retrieval_request=request,
        query_source_authorization=user_token or None,
        connection_timeout=SEARCH_CONNECT_TIMEOUT,
        read_timeout=SEARCH_READ_TIMEOUT,
        retry_total=SEARCH_RETRY_TOTAL,
    )

    _log_activity(result, kb_name, span)

    text = _extract_response_text(result)

    if not text:
        # 権限メタデータが無い / ユーザーに可視なドキュメントが無い場合、
        # エラーではなく空応答になる。どちらが原因かは呼び出し元へ返さない。
        # 原因の切り分けはログと span で行う。
        _logger.info(
            "Knowledge base returned no results.",
            extra={"kb": kb_name, "acl_header_present": bool(user_token)},
        )
    return text
