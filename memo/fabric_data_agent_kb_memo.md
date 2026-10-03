# 机上メモ: Fabric Data agent 用ナレッジベースの追加 (foundryiq-acl-mcp)

状態: 机上検討のみ。コードは未変更。確認できていない点は「未確認」と明記する。
対象: `src/foundryiq-acl-mcp` (Azure Functions の MCP ツール `foundryiq_knowledge_retrieve`)
前提: 現在は検索インデックスのナレッジソースのみ。将来、Fabric Data agent を足す可能性がある。
      MCP クライアントの LLM が、問い合わせ先 (検索インデックス / Fabric Data agent) を選ぶ想定。

## 1. 方針

ナレッジソースの種類ごとにナレッジベースを分け、ツールの引数でナレッジベースを選ぶ。

- 検索インデックス用 KB (既存)
- Fabric Data agent 用 KB (新規)

理由:
- `kb_client.retrieve()` は `kb_name` 引数を持ち、`_get_client` も KB 名ごとにクライアントをキャッシュしている。複数 KB を扱える作りがすでにある。
- 1 つの KB に両方を入れて `always_query_source` で絞る案は、「ソース選択を飛ばして必ず問い合わせる」とは書かれているが、他のソースを問い合わせない保証は書かれていない (未確認)。分けるほうが確実。

## 2. 認証・認可 (ほぼ変更なし)

- ユーザートークンは `x-ms-query-source-authorization` (scope `https://search.azure.com/.default`) で受け取り、SDK の `query_source_authorization` にそのまま渡す。現状のまま使える。
- Fabric Data agent ナレッジソースは OBO フロー。検索エンジンがこのトークンを Fabric 用トークンに交換し、ユーザーとして Data agent を呼ぶ。
- AI Search へのサービス認証 (Function の MI + Search Index Data Reader) も別途必要で、現状のまま。ヘッダーのトークンは、これを置き換えない。
- `ingestionPermissionOptions` は不要 (インデックスを持たず、取得時にユーザーのトークンで直接問い合わせる種別のため)。
- Foundry の OAuth identity passthrough のような、ユーザーの同意リンクのフローは出てこない。OBO の事前同意が必要かどうかは、Learn に記載がなく未確認。

## 3. 変更箇所 (案)

### 3.1 ツール引数 (`tools/knowledge_retrieve.py`)
- 任意引数 `source` を追加。取り得る値は固定の短い名前 (例: `docs` / `fabric`)。
- description に、それぞれの用途を書いて LLM が選べるようにする。
  - `docs`: 文書の検索
  - `fabric`: Fabric のデータへの分析的な質問
- 省略時は既存の KB (現在の挙動のまま)。

### 3.2 名前の対応表 (サーバー側で固定)
```python
KNOWLEDGE_BASES = {
    "docs":   {"kb": "<検索インデックスのKB名>", "kind": "searchIndex"},
    "fabric": {"kb": "<Fabric用のKB名>",         "kind": "fabricDataAgent"},
}
```
- LLM が渡した文字列を、そのまま KB 名やソース名に使わない。表にない値は拒否する。
- 中身は環境変数から読んでもよい。

### 3.3 リクエスト組み立て (`kb_client._build_request`)
- `kind == "fabricDataAgent"` のときだけ `knowledge_source_params` を足す。
```python
from azure.search.documents.knowledgebases.models import FabricDataAgentKnowledgeSourceParams

knowledge_source_params=[
    FabricDataAgentKnowledgeSourceParams(
        knowledge_source_name="<Fabric ナレッジソース名>",
        include_reference_source_data=True,
    )
]
```
- `include_reference_source_data=True` がないと `references[].source_data` が入らない。
- `searchIndex` は従来どおり `knowledge_source_params` なし。
- 現在のコメント「`knowledge_source_params` は指定しない」の方針を、この分岐に合わせて書き換える。

SDK (12.1.0b1) で存在を確認済みのもの:
- `FabricDataAgentKnowledgeSourceParams` が存在し、`knowledge_source_name`、`include_reference_source_data`、`always_query_source`、`fail_on_error` などを持つ。
- `KnowledgeBaseFabricDataAgentReference` が `source_data: Optional[dict[str, Any]]` を持つ。
- `KnowledgeBaseFabricDataAgentActivityRecord` が存在する。

### 3.4 応答の整形 (`kb_client._extract_response_text` 付近)
- 現在は `response[].content[].text` だけを読む。Data agent の回答は `references[].source_data.fabricAnswer` に入ると Learn に書かれているため、そこも読む必要がある。
- `references[].type` で振り分ける。
  - `searchIndex`: 従来どおり `response` のテキスト
  - `fabricDataAgent`: `fabricAnswer` と `fabricEmbeddedResources` (`title` / `mimeType` / `content`) を整形
- 方針: `fabricAnswer` と `fabricEmbeddedResources` を取り出して整形して返す (キーを決め打ちする方式)。返すデータが最小で、トークンが少ない。
  - 検討した他の方式: `references` を JSON で丸ごと返す (キー名を知らなくてよいが、トークンが増え、`rerankerScore` や `workspaceId` / `dataAgentId` なども出る)、`type` と `source_data` だけに絞って返す (折衷案)。
  - 決め打ちの弱点: 実応答のキー名が Learn の応答例とずれると、何も取れない。実装前に実応答のダンプで確認する (5 章の表を参照)。

### 3.5 「結果なし」の判定
- `kb_client.py` の `if not text:` と、`knowledge_retrieve.py` の `"No results."` は、`text` が空のときに結果なしとして扱う。
- Fabric の回答が `references` にだけ入る場合、回答があるのに「結果なし」になる。`text` と `references` の両方が空のときだけ結果なしにする。

### 3.6 その他の設定
- reasoning effort: Data agent は `minimal` 不可 (`low` か `medium`)。`SEARCH_RETRIEVAL_REASONING_EFFORT` が KB 共通の設定なので、`minimal` にしていないか確認。KB ごとに変えたいなら対応表に持たせる。
- タイムアウト: Data agent の問い合わせは時間がかかることがある。`SEARCH_MAX_RUNTIME` (50 秒) と `SEARCH_READ_TIMEOUT` (60 秒) で足りるかは実測が必要。MCP クライアント側の 100 秒タイムアウトとの関係も見る。

### 3.7 activity 配列 (Data agent のレコード)

`include_activity=True` のとき、Data agent の問い合わせ 1 回につき `type: "fabricDataAgent"` のレコードが 1 件入る。SDK 12.1.0b1 の `KnowledgeBaseFabricDataAgentActivityRecord` と、Learn の応答例で確認。

| フィールド | 内容 |
|---|---|
| `id` | activity の ID (`references[].activity_source` と対応) |
| `type` | `"fabricDataAgent"` |
| `knowledge_source_name` | 問い合わせたナレッジソース名 |
| `query_time` | 問い合わせ時刻 |
| `elapsed_ms` | 所要時間 (ミリ秒) |
| `count` | reranker の閾値を超えた取得件数 |
| `fabric_data_agent_arguments.search` | Data agent に渡した検索文字列 |
| `error` | 失敗時だけ入る。失敗の詳細 |
| `warning` | スコア閾値で落とした / トークン上限で切り詰めた / タイムアウトなどの警告 |
| `image_serving` | 画像配信の統計 |

Learn の応答例:
```json
{
  "type": "fabricDataAgent",
  "id": 1,
  "knowledgeSourceName": "my-fabric-data-agent-ks",
  "queryTime": "2026-05-11T19:37:11.600Z",
  "count": 1,
  "fabricDataAgentArguments": { "search": "my query" }
}
```

同じ配列には、ほかの種類のレコードも並ぶ: `modelQueryPlanning` / `modelAnswerSynthesis` (LLM のトークン消費)、`agenticReasoning` (`reasoning_tokens`)、各ナレッジソースのレコード (`searchIndex` など)。

今のコードとの関係:
- `kb_client._log_activity` は `getattr` で拾う作りなので、Data agent のレコードも読める。ただし拾うのは `error` / `warning` / トークン数だけで、`elapsed_ms` と `fabric_data_agent_arguments.search` は記録しない。
- Data agent は応答が遅いことがあるため、`elapsed_ms` を span の属性に出すと切り分けに役立つ。ただし `_log_activity` のコメントには「サブクエリが並列実行されるので `elapsed_ms` の単純合計は実時間と一致せず、所要時間は span の duration を見る」という方針がある。この方針との兼ね合いは要判断。
- `error` が入るのは「そのソースが失敗したとき」だけ。ソース単位の失敗は、例外にならず 206 Partial Content で返る点は、現状と同じ。

## 4. 環境側で必要なこと

- Fabric Data agent の `knowledgeSource` (`kind: fabricDataAgent`、`workspaceId` と `dataAgentId`) を作成する。
- そのナレッジソースを持つ、Fabric 用のナレッジベースを作成する。
- 検索サービスと Fabric ワークスペースが同じ Entra テナントにあること。
- Data agent が公開済みで、呼び出しユーザーが Data agent と元データに読み取り権限を持つこと。
- Fabric 容量は F2 以上 (Data agent の前提)。

### 4.1 ユーザーに必要な Fabric 側の権限

Foundry IQ の Data agent ナレッジソースの場合、ユーザーに必要な Fabric 側の権限は、Data agent への読み取り権限と、Data agent が使うデータソースごとの最小限の権限。

- 権限が足りないと、Data agent は開けても、足りないデータソースに触れるクエリは、認可エラーになるか、空の結果になる。
- Data agent は、呼び出したユーザーの資格情報で動く。RLS と CLS も含めて、ユーザーの権限がそのまま適用される。
- データも一緒に共有する必要がある。Data agent を共有するときは、元になるデータへのアクセスも、共有する必要がある。

その他の前提 (Data agent 全般):
- Data agent は公開済みであること (下書きだけでは、他のユーザーはクエリできない)。
- Data agent とその呼び出し側 (ここでは、検索サービス) が、同じテナントにあること。
- Fabric 容量は F2 以上で、AI 向けのクロスジオ処理が有効なこと (テナント設定)。
- Fabric のライセンスが、ユーザーにも必要 (Fabric IQ の記述)。

出典についての注意:
- 上の内容は、Fabric 側の Data agent の記述 (sharing and permission management など) に基づく。
- Foundry IQ の Data agent ナレッジソースのページには、Fabric 側でユーザーに必要な権限の記述はない。Foundry IQ 経由でも同じになるかは、Fabric 側の前提に従うと読んだ推測で、確認していない (5 章を参照)。

## 5. 未確認事項 (実環境で確かめる)

| 項目 | 内容 |
|---|---|
| API バージョン / SDK | 現在の既定は `2026-05-01-preview`。Learn の Fabric ナレッジソースのページは `2026-08-01-preview`。前者で `fabricDataAgent` が使えるかは**未確認**。ダメなら `2026-08-01-preview` に上げる。SDK 12.1.0b1 は `2026-08-01-preview` に**非対応**で、上げるなら 12.1.0b2 が必要 (確認済み。6 章を参照) |
| `response` の中身 | Fabric 系で `response[].content[].text` に何が入るか (回答が入るのか、空か) |
| `references[].type` | SDK では `KnowledgeBaseReferenceType` の enum。`"fabricDataAgent"` との比較が通るか |
| `source_data` のキー | `fabricAnswer` / `fabricEmbeddedResources` が実応答でも同名か (Learn の応答例に基づく) |
| OBO の事前同意 | Learn に記載なし。同意が必要なテナントがあるか |
| Fabric 側のユーザー権限 | Foundry IQ のナレッジソースのページに記述なし。Fabric の Data agent の前提 (4.1) に従うと読んだ推測 |
| `DataAgent.Execute.All` | Foundry の Fabric IQ ツール (BYO Entra の接続) の説明にだけ出てくる。ナレッジソースの説明には記載なし。検索エンジンが交換する Fabric トークンのスコープと、同意の要否は未確認 |
| `always_query_source` | 他のソースを問い合わせない保証があるか (KB 分離の判断理由) |

## 6. SDK 12.1.0b1 から 12.1.0b2 に上げた場合の影響 (確認済み)

b1 (`.venv`) と b2 (`pip download` したもの。`.venv` には未インストール) の両方に同じスクリプトを当て、さらに b2 のリリースノート (Breaking Changes) を読んで確認した。結論: 現在の function コードが使っている API は、b2 でもそのまま使える。

API バージョンへの対応:
- 12.1.0b1 (`.venv`、`requirements.txt` で固定): `knowledgebases` の `api_version` 既定は `2026-05-01-preview`。`ApiVersion` は `V2026_05_01_PREVIEW` までで、`2026-08-01-preview` は存在しない。
- 12.1.0b2 (PyPI の次のプレリリース。`pip download` で中身のみ確認、`.venv` には未インストール): `ApiVersion.V2026_08_01_PREVIEW` があり、`DEFAULT_VERSION` も `2026-08-01-preview`。`FabricDataAgentKnowledgeSourceParams` も公開されている。

照合して同一だったもの:
- `KnowledgeBaseRetrievalRequest` の `intents` / `output_mode` / `max_output_documents` / `max_output_size` / `retrieval_reasoning_effort` / `include_activity` / `max_runtime_in_seconds`
- `KnowledgeRetrieval{Minimal,Low,Medium}ReasoningEffort`、`KnowledgeRetrievalOutputMode.EXTRACTIVE_DATA`、`KnowledgeRetrievalSemanticIntent`
- `retrieve(retrieval_request, *, query_source_authorization, **kwargs)`。b2 は `query_work_iq_source_authorization` が増えただけ。タイムアウト・リトライは `**kwargs` 経由で変わらない
- レスポンスの `response` / `activity` / `references`、`_log_activity` が読む activity の属性 (`input_tokens` / `output_tokens` / `input_tokens_count` / `output_tokens_count` / `reasoning_tokens` / `error` / `warning` / `type` / `id`)

b2 の破壊的変更と、今のコードへの影響:

| 変更 | 影響 |
|---|---|
| activity record の `model_name` を `model` に変更 (query planning / answer synthesis / web summarization) | なし。コードは `model_name` を読んでいない (コメントに名前が出るだけ) |
| `ApiVersion.V2026_05_01_PREVIEW` を `V2026_08_01_PREVIEW` に置き換え、既定も変更 | 設定次第 (下記) |
| Work IQ 関連 (`WorkIQAttribution` の削除など) | なし (未使用) |
| `list_indexes` の引数変更など | なし (未使用) |
| Python 3.9 のサポート終了 (3.10 以上が必要) | **要確認**。ローカル `.venv` は 3.11 で問題なし。Function アプリの Python バージョンは未確認 |

API バージョンの扱い:
- `kb_client.py` は `SEARCH_API_VERSION` を明示して渡している。SDK の既定が変わっても影響を受けない。
- b2 でも文字列 `"2026-05-01-preview"` を渡すこと自体は、操作側のバージョン一覧に残っているので通る見込みだが、実際には呼んでいない (未確認)。
- `2026-08-01-preview` に切り替えると、サービス側の挙動が変わる可能性がある。移行ガイドは未確認。

その他:
- `azure-core` は `.venv` が 1.41.0 で、b2 の要件 (1.37.0 以上) を満たす。
- 更新するときに直す箇所: `src/foundryiq-acl-mcp/requirements.txt` の固定とコメント、`shared/kb_client.py` の冒頭の説明文 (b1 と `2026-05-01-preview` の記述)。

上げ方の案 (SDK 更新とサービス側のバージョン変更を分ける):
1. `requirements.txt` を `12.1.0b2` に上げるだけにして、`SEARCH_API_VERSION` は `2026-05-01-preview` のままにする。
2. 既存の動作に変化がないことを確認する。
3. その後で `SEARCH_API_VERSION` を `2026-08-01-preview` に切り替えて、Fabric の確認に進む。

## 7. 進め方 (案)

0. (必要なら) SDK を 12.1.0b2 に上げる。6 章の手順どおり、まず `SEARCH_API_VERSION` は据え置きにする。
1. 最小変更: `knowledge_source_params` の追加と、`response` / `references` のダンプだけを入れて、実際の応答を確認する。
2. 未確認事項の結果をこの表に反映する。
3. 整形処理と「結果なし」の判定を直す。
4. ツール引数 `source` と対応表を入れる。

## 参考

- Fabric Data Agent ナレッジソース: https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-fabric-data-agent
- Fabric Ontology ナレッジソース: https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-fabric-ontology
- Retrieve (権限の強制と応答の見方): https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-retrieve
- ナレッジソース一覧: https://learn.microsoft.com/azure/search/agentic-knowledge-source-overview
