# 実験メモ: 通常のプロンプトエージェントと Copilot harness 版で、A2A の挙動はどう違うか (同期/非同期、成功/エラー)

実施日: 2026-10-29 (JST。ログの時刻は UTC で 2026-10-28 22:04〜2026-10-29 02:44)
対象: Foundry のプロンプトエージェント2種 (どちらも `gpt-5.4`、A2A 有効)。**1つの Foundry アカウントのみ**で実験し、Foundry の A2A エンドポイントに直接送った。

- **通常**: `tartaria-agent` (このリポジトリのエージェント。ハーネスなし。Foundry IQ のナレッジベースを MCP ツールで使う)
- **ハーネス版**: `tartaria-harness-agent` (今回、Copilot harness を有効にして作成。同じ Foundry IQ ツール + スキル。設定は 2.4)

結論: **成功時は、どちらも同じ形で結果が返る (最初の状態名と、アーティファクトの数が違う)。エラー時は、通常のエージェントは、同期なら JSON-RPC の `error` (`-32099`)、非同期なら `failed` のタスクで返す。ハーネス版は、同期でも非同期でも、`error` ではなく `failed` のタスクで返り、理由は付かない。**
(実験は小規模で、各条件 1〜数回。傾向の確認であり、統計的な保証ではない)

### プレースホルダー (環境を特定しうるものだけ)

| 表記 | 意味 |
| --- | --- |
| `<アカウント>` | 実験した Foundry アカウント (westus) |
| `<リソースグループ>` | そのアカウントのリソースグループ |
| `<ナレッジ文書>` | 回答の出典になったファイル |
| `<AI Search サービス>` | Foundry IQ のナレッジベースがある AI Search サービス |

## 1. 結果のまとめ

| | 通常 (`tartaria-agent`) | ハーネス版 (`tartaria-harness-agent`) |
| --- | --- | --- |
| **成功・同期** | `completed` のタスク。`artifacts` 1件 (回答)。約10秒 | `completed` のタスク。`artifacts` 1〜2件 (前置き + 回答)。30〜46秒 |
| **成功・非同期** | 最初に `submitted` → `working` → `completed` | 最初に `working` → `completed` (44〜60秒) |
| **エラー・同期** | **JSON-RPC `error`** (`-32099`、`reason` で原因を区別)。約10〜14秒 | **`error` なし**。`result` の中の `failed` のタスク (`artifacts` 空、理由なし)。37〜46秒 |
| **エラー・非同期** | **送信時は成功の形** (`submitted`)。`tasks/get` / `GetTask` でも **`error` にならず、`result` の `state: failed`** で返る (理由なし)。約27秒で `failed` | **送信時は成功の形** (`working`)。`tasks/get` / `GetTask` でも **`error` にならず、`result` の `state: failed`** で返る (理由なし)。約39秒で `failed` |

> **注意**: HTTP ステータスは、エラー時も含めて、どれも **200** が返る。失敗は、HTTP ステータスではなく、本文の JSON-RPC `error` か、`result` の `state: failed` でのみ分かる。

## 2. 環境と前提

| 項目 | 値 |
| --- | --- |
| Foundry アカウント | `<アカウント>` (westus)。RG: `<リソースグループ>`。プロジェクト: `ai-foundry-project` |
| `tartaria-agent` | このリポジトリで作成しているエージェント (ハーネスなし、`gpt-5.4`、Foundry IQ の MCP ツール、ガードレール付き)。設定の詳細は、リポジトリの定義を参照 |
| `tartaria-harness-agent` | 今回、REST API で作成したエージェント (Copilot harness)。設定の全体は 2.4 |
| モデルのデプロイ | `gpt-5.4` (GlobalStandard)。通常の容量は **5000** |
| 呼び出し方 | `az account get-access-token --resource https://ai.azure.com` のトークンで、`https://<アカウント>.services.ai.azure.com/api/projects/ai-foundry-project/agents/<エージェント名>/endpoint/protocols/a2a` に直接 POST |

### 2.1 容量 (capacity) と TPM

容量 5000 のデプロイの `rateLimits` は、トークン 5,000,000/60 秒、リクエスト 50,000/60 秒。つまり **容量 1 = 1,000 トークン/分、10 リクエスト/分** (「1 TPM」ではない)。短い質問なら、容量 1 でも収まることがある。失敗の再現には、長めの質問や、連続・並列の送信が必要だった。

### 2.2 ナレッジベースのモデル

ナレッジベース (Foundry IQ) は、内部でモデルを呼ぶ (ナレッジベースの定義の `models[]`、`retrievalReasoningEffort`)。このモデルの接続先は、実験したアカウントの `gpt-5.4` のデプロイ。そのため、通常エージェントのツール (`knowledge_base_retrieve`) は、エージェント自身のモデルに加えて、同じデプロイをもう一度使う。容量を下げると、両方が制限される。

### 2.3 エラーの起こし方 (モデルの容量を 1 にする)

モデルのデプロイの容量 (TPM) を最小の **1** (1,000 トークン/分、10 リクエスト/分) に下げて、レート制限を起こした。

1. 現在の容量を確認する (元は **5000**)。
2. 同じモデル・バージョン・SKU のまま、容量だけを 1 にして、デプロイを更新する。

   ```bash
   az cognitiveservices account deployment create -g <リソースグループ> -n <アカウント> \
     --deployment-name gpt-5.4 --model-format OpenAI --model-name gpt-5.4 \
     --model-version 2026-03-05 --sku-name GlobalStandard --sku-capacity 1
   ```

   更新は、数秒で `Succeeded` になった (アクティビティログでは、開始から約3秒)。多くの試験で、送信の前に約20秒待った。
3. A2A のエンドポイントに、長めの質問で送る。
   - 同期: v1.0 `SendMessage` と v0.3 `message/send` (`blocking: true`) を、1本ずつ順番に。
   - 非同期: v0.3 (設定なし) と v1.0 (`returnImmediately: true`) を、各4本、まとめて送り、`tasks/get` / `GetTask` で完了までポーリング。
4. 結果 (`error` か `failed` のタスクか、所要時間) を記録する。
5. 試験後、容量を 5000 に戻す (手順は 9 章)。

注意:

- 容量 1 は、短い質問なら収まることがあり、**必ず 429 になるわけではない**。長めの質問や、連続・並列の送信が必要だった (2.1)。
- 容量の変更は、同じデプロイを使う他のエージェントと、ナレッジベース内部のモデル (2.2) にも影響する。
- 変更が実際に効くまでの時間は、確認していない (戻した直後のエラーは、反映の遅れの可能性がある。8 章)。

### 2.4 tartaria-harness-agent の設定

今回、REST API で作成した (リポジトリの IaC には含まれない)。`<project>` は `https://<アカウント>.services.ai.azure.com/api/projects/ai-foundry-project`。

**1. スキルの作成** (`POST <project>/skills/tartaria-foundryiq/versions?api-version=v1`、ヘッダー `Foundry-Features: Skills=V1Preview`)。`inline_content` の内容:

- `description`: "Answer questions about Tartaria (タルタリア) by always running the FoundryIQ knowledge base tool first."
- `instructions`:

  ```markdown
  # Tartaria knowledge skill

  Use this skill whenever the user asks about Tartaria (タルタリア), Great Tartary, Tartarian architecture, the mud flood, or any related topic.

  ## Instructions

  - ALWAYS call the `knowledge_base_retrieve` tool of the FoundryIQ MCP server before answering. Do not answer from your own knowledge.
  - Base the answer solely on the retrieved information. Do not add your own opinions, evaluations, or judgements.
  - Present conspiracy-theory claims exactly as described in the source, without correction or commentary.
  - Keep the source references that the tool returns.
  - If the tool returns nothing relevant, say that the knowledge base has no information on the topic.
  ```

**2. エージェントの作成** (`POST <project>/agents/tartaria-harness-agent/versions?api-version=v1`、ヘッダー `Foundry-Features: MicrosoftCopilot=V1Preview,Skills=V1Preview`)。`definition`:

```json
{
  "kind": "prompt",
  "model": "gpt-5.4",
  "reasoning": { "effort": "low" },
  "instructions": "You are a knowledge agent about Tartaria (タルタリア). Follow the tartaria-foundryiq skill for every question about Tartaria.",
  "harness": { "type": "microsoft_copilot_preview" },
  "tools": [
    {
      "type": "mcp",
      "server_label": "FoundryIQ",
      "server_url": "https://<AI Search サービス>.search.windows.net/knowledgebases/kb-tartalia-noacl-gen2/mcp?api-version=2026-08-01-preview",
      "project_connection_id": "FoundryIQ",
      "allowed_tools": { "tool_names": ["knowledge_base_retrieve"] },
      "require_approval": "never"
    },
    {
      "type": "microsoft_copilot_toolset_preview",
      "configs": [
        { "name": "web", "enabled": false },
        { "name": "shell", "enabled": false }
      ]
    }
  ],
  "skills": [
    { "type": "skill_reference", "name": "tartaria-foundryiq", "version": "1" }
  ]
}
```

- MCP ツール (Foundry IQ) は、`tartaria-agent` と同じ定義 (既存のプロジェクト接続 `FoundryIQ`、`kb-tartalia-noacl-gen2`、承認なし)。
- ハーネスのツールは、`web` と `shell` だけをオフにした。`filesystem_read`、`filesystem_write`、`subagents` は既定 (有効) のまま。
- 作成後の定義では、`skills` は `{ "name": "tartaria-foundryiq", "version": "1" }` の形で保存された。

**3. A2A の有効化** (`PATCH <project>/agents/tartaria-harness-agent?api-version=v1`):

```json
{
  "agent_card": {
    "description": "Tartaria knowledge agent (Copilot harness, Foundry IQ)",
    "version": "1.0",
    "skills": [
      {
        "id": "tartaria-qa",
        "name": "Tartaria Q&A",
        "description": "Answers questions about Tartaria using the Foundry IQ knowledge base"
      }
    ]
  },
  "agent_endpoint": { "protocol_configuration": { "responses": {}, "a2a": {} } }
}
```

**設定していないもの**: ガードレール (`rai_config`。`tartaria-agent` には付いている)、Foundry の web search ツール、Toolbox、ナレッジの内容に応じた注記の指示 (`tartaria-agent` の instructions にはある)。

## 3. A2A の仕様と Foundry のバージョン選択

| | v0.3 | v1.0 |
| --- | --- | --- |
| メソッド名 | `message/send`、`tasks/get` | `SendMessage`、`GetTask` |
| 設定項目 | `configuration.blocking` | `configuration.returnImmediately` |
| 未指定時の既定 | **仕様に明記なし** (§7.1.2) | **`false` = 待つ (同期)**。"Operations are blocking by default" |
| 戻り値 | `Task` または `Message` | `Task` または `Message` |

- Foundry は、`A2A-Version` ヘッダー、`?a2a-version=` のクエリ、または版付きのエージェントカードでバージョンを選ぶ。**どれも指定しないと v0.3 として扱う** (v0.3 はプレビュー、v1.0 は GA)。
- v1.0 の JSON-RPC では、パーツに `kind` がない。ロールは `ROLE_USER`。状態名は `TASK_STATE_COMPLETED` のように大文字。v0.3 は `kind: "task"`、状態名は小文字。
- v1.0 は JSON-RPC のみ。v0.3 は HTTP+JSON も可。ストリーミングは非対応 (カードの `capabilities.streaming` が `false`)。
- エージェントカードは、`.well-known/agent-card.json` が 404 (版付き URL を案内)。`agentCard/v1.0` と `agentCard/v0.3` は 200。

### 3.1 エラーについての仕様 (v1.0 §3.3.2、§5.4、§9.5)

- エラーは、認証、認可、検証、リソース、システムの5カテゴリ。システムエラーは、HTTP 500/503、gRPC INTERNAL/UNAVAILABLE、JSON-RPC `-32603` に対応し、例にレート制限超過も挙がっている。
- A2A 固有コードは `-32001` (TaskNotFound) 〜 `-32009` (VersionNotSupported)。`-32001`〜`-32099` の範囲を使う、とある。**`-32099` の個別の定義はない**。
- タスクの失敗は、`TASK_STATE_FAILED` (エラーで終了した終端状態) で表す。`TaskStatus` に任意の `message` はあるが、理由を入れる規定はない。
- **タスクの実行失敗を、`error` で返すか `FAILED` のタスクで返すか、同期・非同期のどちらで `error` にするか、を定めた記述はない。** 同期 (blocking) は「最新のタスク状態を含めて返す」とあり、失敗は `FAILED` のタスクで返ると読める (推論)。
- 非同期の失敗は、`GetTask`、`SubscribeToTask`、プッシュ通知で知る。

つまり、「同期は `error`、非同期は `failed` のタスク」は、**Foundry の通常のプロンプトエージェントの実装の挙動**であり、仕様が求めたものではない。ハーネス版の挙動 (同期でも `failed` のタスク) は、仕様の素直な読み方に近い。

## 4. 比較: 成功時

### 4.1 同期 (成功)

| 呼び出し | 通常 | ハーネス版 |
| --- | --- | --- |
| v1.0 `SendMessage` (設定なし) | `TASK_STATE_COMPLETED`、`artifacts` 1件、約11秒 (短い質問) | `TASK_STATE_COMPLETED`、`artifacts` 2件、**46.3秒** |
| v0.3 `message/send` + `blocking: true` | `completed`、`artifacts` 1件、約10秒 | `completed`、`artifacts` 2件、**29.9秒** |

- 通常の回答は、ナレッジベースの出典付き (`【5:5†source】` のような形)。ハーネス版の回答は、`[ref_id: 0, "<ナレッジ文書>"]` のような出典付き。
- **ハーネス版の `artifacts` は、1〜2件**。1件目は前置き ("I'm pulling the knowledge base results and reading the most relevant excerpts.")、2件目が回答。非同期 v0.3 で、1件だけの回もあった。

### 4.2 非同期 (成功)

| 呼び出し | 通常 | ハーネス版 |
| --- | --- | --- |
| v0.3 `message/send` (設定なし) | 最初の応答が **`submitted`** (`artifacts` 空)。ポーリングで `working` (約10秒後) → `completed` (約20秒後) (短い質問、容量 1) | 最初の応答が **`working`** (送信に2.5〜8秒)。`completed` は約44〜46秒後。`artifacts` は2件 (1回目) / 1件 (2回目) |
| v1.0 `SendMessage` + `returnImmediately: true` | **未確認** (成功の場合は試していない。失敗時の最初の状態は `TASK_STATE_SUBMITTED`) | 最初の応答が **`TASK_STATE_WORKING`** (送信に2.5〜3.3秒)。`TASK_STATE_COMPLETED` は約45〜60秒後。`artifacts` は2件 |

- **最初の状態が違う**: 通常は `submitted`、ハーネス版は `working`。
- 完了時の回答の形は、同期と同じ。

### 4.3 回答の内容 (ハーネス版、同期と非同期)

出典は、すべて `<ナレッジ文書>`。回答は、ナレッジの記述をそのまま提示する形で、呼び出しごとに、取れる抜粋や要約が変わる (同じ質問でも、焦点が違う回があった)。ナレッジには、陰謀論的な主張が含まれており、回答もそのまま提示する。**通常エージェントの instructions にある注記の指示は、ハーネス版には入れていない** (回答にも注記は付かなかった)。また、非同期 v1.0 の回答の末尾に、「If you want a narrower summary, I can describe …」という提案の文が付いていた。

### 4.4 ハーネス版の `artifacts` が2件になる理由

並列実行ではなく、**前置きのメッセージ + 最終回答が、別々のアーティファクトになる**ためと見られる (推測)。App Insights のスパンは順次実行で、サブエージェントの形跡はない。アーティファクトの ID は `msg_…` で、件数は実行ごとに変わった (前置きをモデルが出したかどうか)。

### 4.5 ハーネス版のツール呼び出し (App Insights)

ハーネス版の1回の実行のスパン:

`chat gpt-5.4` → `execute_tool skill` (7ms、スキルの読み込み) → `chat` → `execute_tool managed_tools-FoundryIQ___knowledge_base_retrieve` (6.1秒) → `chat` → `execute_tool view` (失敗。ハーネスのファイル読み取り) → `chat` → `execute_tool …knowledge_base_retrieve` (4.5秒)。

起動時に、スキルの取得 (`GET .../skills/tartaria-foundryiq/version`) が 200 で成功している。スキルの指示どおり、Foundry IQ のツールが実行された。

## 5. 比較: エラー時

エラーは、`gpt-5.4` の容量を 1 (1,000 TPM、10 RPM) に下げて、長めの質問 (「タルタリアについて、背景や経緯を詳しく、出典付きで」) で起こした。

### 5.1 同期 (エラー)

**通常**: HTTP 200 の **JSON-RPC `error`** (`-32099`)。

| 試験 (容量 1) | 結果 | 所要時間 |
| --- | --- | --- |
| v1.0 `SendMessage` を1本ずつ (長めの質問) | 1〜3本目は成功 (42.1、35.9、74.5 秒。待ちが入った)、4本目が `-32099`、`"The tool request could not be completed. Check the tool configuration and input."`、`reason: TOOL_USER_ERROR` | 4本目: 11.2 秒 |
| v1.0 / v0.3 `blocking: true` (短い質問。容量を戻した直後の 5000 と、容量 1) | `-32099`、`reason: TOOL_USER_ERROR` (v0.3 は `data.code: ToolUserError`)。いずれも `error` で返った | 9.8〜14.3 秒 |

v1.0 の応答:

```json
{"jsonrpc":"2.0","id":"q4","error":{"code":-32099,
 "message":"The tool request could not be completed. Check the tool configuration and input.",
 "data":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"TOOL_USER_ERROR","domain":"ai.azure.com"}]}}
```

v0.3 (`blocking: true`) では、`error.message` は同じで、`error.data` が `{"code":"ToolUserError"}` になる。

- `error.data[0].metadata` は**ない** (存在しないタスクの `-32603` では、`metadata.detail` が付いていた)。
- `TOOL_USER_ERROR` は、2.2 の通り、**ナレッジベース内部のモデル呼び出しが、容量 1 でレート制限された**ためと整理した (ユーザーの指摘による。応答には理由が出ないため、他のツール失敗とは、応答だけでは区別できない)。
- 容量を 1 から 5000 に戻した直後にも、1度、`TOOL_USER_ERROR` が出た (推測: 変更が反映される前だった。未確認)。

**ハーネス版**: HTTP 200 で、**`error` なし**。`result` の中の `failed` のタスク。

| 試験 (容量 1) | 結果 | 所要時間 |
| --- | --- | --- |
| v1.0 (1回目) | **`TASK_STATE_COMPLETED`** (`artifacts` 2件。推測: 内部の再試行の間に、枠が空いて成功) | 112.3 秒 |
| v0.3 blocking | `failed`、`artifacts` 0件、`status.message` なし | 46.3 秒 |
| v1.0 (再試行) | `TASK_STATE_FAILED`、`artifacts` 0件、`status.message` なし | 37.4 秒 |

- App Insights では (ハーネス版とは別構成のエージェントの失敗で確認したもの。ハーネス版の失敗時のスパンは未確認)、ハーネス内のモデル呼び出し (`invoke_agent github-copilot-preview-…`) が、**約1秒ごとに 500 で、1回の実行につき 6〜10 回ほど連続**していた。外側の `invoke_agent` は 30〜34 秒かかり、`resultCode` は `0` (成功扱い)。ハーネスが 429 を内部で再試行し、およそ30〜45秒で諦めて `failed` のタスクを返した、と読める。
- **失敗までの時間が、通常 (約10〜14秒) より長い**。同じ条件でも、成功することがある (112 秒)。

### 5.2 非同期 (エラー)

| | 通常 | ハーネス版 |
| --- | --- | --- |
| 送信時の応答 | `submitted` / `TASK_STATE_SUBMITTED` (`artifacts` 空) | `working` / `TASK_STATE_WORKING` (`artifacts` 空) |
| ポーリング | 約27秒以内に **`failed` / `TASK_STATE_FAILED`** (8本とも) | 約39秒後に **`failed` / `TASK_STATE_FAILED`** (v0.3、v1.0 とも) |
| `error` | **なし** | **なし** |
| 理由 (`status.message`、`artifacts`) | なし (`artifacts` 空) | なし (`artifacts` 空) |

- 通常の試験は、v0.3 設定なし ×4 + v1.0 `returnImmediately: true` ×4 を、まとめて送った。
- どちらも、送信時は成功の形で、`tasks/get` / `GetTask` でも `error` にならない。クライアントは、「失敗した」ことしか分からず、レート制限かツールの失敗かは区別できない。

### 5.3 エラー時の違いが生まれる理由 (推測)

- **通常のプロンプトエージェント**: Foundry のサービスが、エージェントの失敗を JSON-RPC の `error` に変換して返す (同期)。
- **ハーネス版**: ハーネスが、モデルの制限を内部で再試行し、最後に `failed` のタスクとして完了させる。外側のスパンは成功扱いになる。
- ハーネスがプレビューであることが理由かどうかは、確認できていない (Learn に、A2A のエラーの返し方の記述はない)。GA で挙動が変わるかは、現時点では分からない。

## 6. `-32099` について

- A2A v1.0 仕様 (§5.4、§9.5) に、`-32099` の個別の定義はない (`-32010`〜`-32099` にも、個別の定義はない)。Microsoft Learn の Foundry の A2A のドキュメントにも、記載はなかった。
- 実機では、Foundry が `-32099` を独自のエラーに使い、**原因を `reason` (v1.0 の `error.data[0]`) / `data.code` (v0.3) で区別**しているとみられる。今回確認できたのは次の1つ。

| 原因 | v1.0 の `reason` | v0.3 の `data.code` | `error.message` |
| --- | --- | --- | --- |
| ツールの失敗 (ナレッジベースのモデルのレート制限と整理。2.2) | `TOOL_USER_ERROR` | `ToolUserError` | The tool request could not be completed. Check the tool configuration and input. |

- `-32099` は、エラーコードとしては1種類で、原因の区別は `reason` でしかできないとみられる。`reason` の一覧は、公式には見つからなかった。
- プロトコルレベルのエラー (モデルを使わない) は、通常でもハーネス版でも、`error` で返る: 不明なメソッドは `-32601`、必須項目の欠落は `-32602`、存在しないタスクの `tasks/get` / `GetTask` は `-32603` (`Received 400 from a service request`)。v0.3 は詳細が `error.message`、v1.0 は `error.data[0].metadata.detail` (`-32602` だけ `data[0].fieldViolations[].description`)。
- JSON-RPC 2.0 本体が `-32000`〜`-32099` を「実装定義のサーバーエラー」として予約している、という点は、私の知識によるもので、今回の検索では確認していない。

## 7. 既存ドキュメントの記述との差異 (A2A の挙動に関するもの)

既存のハンズオン資料 (技術解説と README) の A2A の挙動の記述と、実機の結果の差。

1. **非同期で最初に返る状態**: `submitted` は通常のプロンプトエージェントでは正しい。ハーネス版は `working`。
2. **v0.3 の「既定は非同期」**: 仕様は未規定。Foundry の挙動として、と補足するのが正確。
3. **v1.0 の「既定は同期」**: v1.0 を選んだ場合の話。バージョン未指定だと v0.3 になるため、ヘッダー等の指定が前提。
4. **モデルの 429 に由来する失敗が `-32603` で返る**とされている点: 今回は `-32099` (`TOOL_USER_ERROR`) だった。
5. **同期なら `error` で返る**とされている点: ハーネス版には当てはまらない (同期でも `failed` のタスク)。
6. Foundry は v0.3 をプレビュー、v1.0 を GA とし、新規は v1.0 を推奨している。
7. **容量を最小 (1) にする試験**: 容量 1 は 1,000 TPM / 10 RPM で、短い質問では 429 にならない。長めの質問や、連続・並列の送信が必要。容量を下げると、ナレッジベースのモデルも制限され、`TOOL_USER_ERROR` になることがある (2.2)。

## 8. 未確認のこと

- 通常のエージェントの**非同期で、v1.0 `returnImmediately: true` の成功**の挙動 (失敗時の最初の状態が `TASK_STATE_SUBMITTED` であることだけ確認した)。
- 通常のエージェント**自身のモデル**がレート制限されたときの、同期のエラーの形 (今回観察したのは、ナレッジベース側のツール失敗 `TOOL_USER_ERROR` のみ)。
- ハーネス版が、A2A ツールで外部エージェントを呼ぶ方向 (公開して呼ばれる方向のみ確認した)。
- **ハーネスが `error` を返さない理由**: プレビューのためか、内部の再試行と `failed` での完了という構造のためか。
- `Hook handler failed` (`RuntimeError`、約10件。2026-10-29 01:49〜01:50 UTC) の原因。
- `view` ツール (ハーネスのファイル読み取り) が失敗した理由 (`success: False`)。
- ハーネス版の失敗時の App Insights のスパン (内部の再試行の有無。5.1 の観察は、別構成のエージェントのもの)。
- `-32099` の `reason` の公式の一覧。
- 容量を戻した直後に出た `TOOL_USER_ERROR` が、変更の反映の遅れによるものか。
- ハーネス版の `artifacts` が2件になる理由の裏付け (Responses API の `output` の項目との対応は、確認していない)。

## 9. 現在の状態と後始末

- `<アカウント>` の `gpt-5.4` の容量は、最後に確認した時点で **1 のまま** (2026-10-29 の試験後、いったん 1 のままにしている)。他のエージェントも制限される。
- 元に戻す手順 (元は GlobalStandard、容量 5000、モデルバージョン 2026-03-05):

  ```bash
  az cognitiveservices account deployment create -g <リソースグループ> -n <アカウント> \
    --deployment-name gpt-5.4 --model-format OpenAI --model-name gpt-5.4 \
    --model-version 2026-03-05 --sku-name GlobalStandard --sku-capacity 5000
  ```

  または、Terraform が管理しているので `azd up` でも戻る。
- 作成したもの: `tartaria-harness-agent` (バージョン 1) とスキル `tartaria-foundryiq`。
- 試験用スクリプト (非同期の一括送信など) は、セッションのスクラッチ領域にあり、リポジトリには含めていない。

## 10. 参考

- A2A 仕様: <https://a2a-protocol.org/latest/specification/> (v1.0)、<https://a2a-protocol.org/v0.3.0/specification/> (v0.3)
- [Enable incoming A2A on a Foundry agent](https://learn.microsoft.com/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint) (バージョン選択、制限)
- [Use the Microsoft Copilot harness with prompt agents](https://learn.microsoft.com/azure/foundry/agents/how-to/use-tools-skills-copilot-harness)
- [Microsoft Copilot harness in Foundry (devblogs)](https://devblogs.microsoft.com/foundry/microsoft-copilot-harness-in-foundry/)
- [Resilience for long-running hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/long-running-agent-resilience) (ホステッドエージェントの復旧。今回の試験とは別)
