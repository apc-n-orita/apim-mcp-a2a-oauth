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
- **エラーのレイヤーは、分かれている。** プロトコル / RPC 層のエラー (JSON-RPC の `error`) は、リクエストの形式不正、存在しないタスクの参照、メソッドの未対応、認証など、**リクエスト自体が成立しなかった場合**のもの。タスク層の失敗 (`TASK_STATE_FAILED`) は、リクエストは受理されてタスクが実行されたが、推論やツールの実行が失敗した場合の終端状態。
- 「同期は `error`、非同期は `failed` のタスク」と分ける規定は、見当たらない。同期 (blocking) は「最新のタスク状態を含めて返す」とあり、失敗は `FAILED` のタスクで返ると読める。
- 非同期の失敗は、`GetTask`、`SubscribeToTask`、プッシュ通知で知る。

つまり、同期でも `failed` のタスクで返すハーネス版の挙動は、**仕様に沿った挙動**と言える。「同期は `error`、非同期は `failed` のタスク」は、**Foundry の通常のプロンプトエージェントの実装の挙動**といえる。

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

多くの実行では、**前置きのメッセージ + 最終回答が、別々のアーティファクトになる**ためと見られる (推測)。App Insights では、ほとんどの実行で `chat` と `execute_tool` が順次実行されていた。ただし、ハーネスの実行 12 回のうち 1 回は、サブエージェント (`invoke_agent general-purpose`) が動いていた (4.6)。この回の `artifacts` の数との対応は、確認していない。アーティファクトの ID は `msg_…` で、件数は実行ごとに変わった (前置きをモデルが出したかどうか)。

### 4.5 ハーネス版のツール呼び出し (App Insights)

ハーネス版の1回の実行のスパン:

`chat gpt-5.4` → `execute_tool skill` (7ms、スキルの読み込み) → `chat` → `execute_tool managed_tools-FoundryIQ___knowledge_base_retrieve` (6.1秒) → `chat` → `execute_tool view` (失敗。ハーネスのファイル読み取り) → `chat` → `execute_tool …knowledge_base_retrieve` (4.5秒)。

起動時に、スキルの取得 (`GET .../skills/tartaria-foundryiq/version`) が 200 で成功している。スキルの指示どおり、Foundry IQ のツールが実行された。

### 4.6 ハーネス版のスパンの構造 (App Insights)

**入れ子の構造** (ロール `cloud_RoleName` が違うスパンが、次のように入れ子になる):

- Foundry のリクエスト (ロール `agentsv2`): `invoke_agent`
  - ハーネスのランタイム (ロール `github-copilot`): `session.provisioning`、`session.first_turn`、`invoke_agent` (`gen_ai.agent.name` は呼び出したエージェント名)。この `invoke_agent` の親は、外側のリクエスト。
    - `chat gpt-5.4` と `execute_tool …` (4.5 の順に並ぶ。親は、このハーネスの `invoke_agent`)

**Foundry 側 (Responses API) の別名**:

| 記録しているところ | スパン名 | ロール |
| --- | --- | --- |
| Foundry (Responses API) | `invoke_agent github-copilot-preview-<GUID>:<バージョン>` | `responsesapi` |
| ハーネスのランタイム | `invoke_agent` (`gen_ai.agent.name` はエージェント名) | `github-copilot` |

- 通常のエージェントでは、Foundry 側のスパンは `invoke_agent <エージェント名>:<バージョン>` (ロール `responsesapi`、バックグラウンド処理では `responsesapi-worker`) と、エージェント名で記録される。ハーネス版では、この名前の部分が `github-copilot-preview-<GUID>` という内部の識別子になる。
- GUID は、呼び出しごとではなく、**エージェントごとに固定**。ハーネス版のエージェント 2 つで、それぞれ別の GUID で、同じエージェントでは毎回同じ GUID だった。`:` のあとは、エージェントのバージョン。
- この Foundry 側のスパンの親スパンの位置づけは、確認していない (`dependencies` には存在しない)。
- ダッシュボードで、エージェント名で集計すると、この別名が、別のエージェントとして数えられる (二重に見える)。

**サブエージェント**:

- ハーネスの実行 12 回のうち 1 回 (約125秒の実行) で、`execute_tool task` (約89秒) の下に、`invoke_agent general-purpose` (サブエージェント) が入れ子になっていた。
- そのサブエージェントが、自分の `chat` と `execute_tool` (`view`、`skill`、`knowledge_base_retrieve` を 3 つ並列で) を実行した。その間も、親のエージェントの `chat` が並行して記録されていた。
- ハーネスツールの `subagents` は、新規のエージェントでは既定で有効 (今回の設定でも有効のまま)。サブエージェントが使われる条件は、確認していない。

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

- App Insights で、ハーネス版の失敗した実行を 2 件確認した (同期と見られる実行と、非同期と見られる実行)。
  - ハーネスの `chat` スパンが **33〜36 秒**かかり、そのあと `gen_ai.client.operation.exception` のトレース (`traces`) が記録されて終わっていた。`customDimensions` の `github.copilot.message` に、次の内容が残っていた。

    > Failed to get response from the AI model; retried 5 times (total retry wait time: 30.67 seconds) Last error: Model deployment rate limit exceeded. Your requests to gpt-5.4 for gpt-5.4 in westus have exceeded token rate limit. …

    もう 1 件は、再試行 5 回、待ち時間の合計 34.00 秒。`github.copilot.error_type` は `query`。
  - **再試行は、別々のスパンではなく、1 つの `chat` スパンの内側**で行われていた (5 回、待ち時間の合計は約31〜34秒)。
  - ハーネスの `invoke_agent` は `success = false` (`resultCode` は `0`)。外側の Foundry のリクエスト (`agentsv2`) は `success = true`。同期と見られる実行では約45秒、非同期と見られる実行では約1秒で返っていた (処理は、そのあとも続いた)。
  - 同期と見られる実行では、`chat` の前に、`execute_tool …knowledge_base_retrieve` が約8秒で `success = false` になっていた (MCP プロキシの上流の応答は 200。原因は未確認)。
  - **失敗の理由 (レート制限) は、A2A の応答には付かないが、App Insights には残る。**
- 別構成のエージェント (ポータルで作ったハーネス版のテスト用) では、Foundry 側 (`responsesapi`) の `invoke_agent` が、約1秒ごとに 500 で失敗する記録があった (詳細は、分析していない)。
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

### 5.3 エラー時の違いが生まれる理由

- **通常のプロンプトエージェント**: Foundry のサービスが、エージェントの失敗を JSON-RPC の `error` に変換して返す (同期)。(推測) モデルのレート制限 (`rate_limit_exceeded`) は、約1ミリ秒で失敗しており、待ちを伴う再試行はしていない (5.4)。
- **ハーネス版**: ハーネスが、モデルのレート制限を**内部で 5 回再試行し** (待ち時間は合計で約31〜34秒)、最後に失敗する (5.1 の App Insights で確認)。外側の Foundry のリクエストは、成功として記録される。失敗までの時間 (約37〜46秒) は、この再試行の待ち時間とほぼ合っている。
- ハーネスが `error` ではなく `failed` のタスクで返す理由が、プレビューだからなのか、この構造のためなのかは、確認できていない (Learn に、A2A のエラーの返し方の記述はない)。GA で挙動が変わるかは、現時点では分からない。

### 5.4 通常のエージェントの失敗の内訳 (App Insights、001)

通常のエージェントの `invoke_agent <エージェント名>:<バージョン>` が失敗した (`success = false`、`resultCode` 500) スパンを、`error.type` で分けた。`microsoft.foundry.project.id` で、アカウントを区別した (以下は 001 のみ。17 件)。

| `error.type` | 件数 | かかった時間 | 内容 |
| --- | --- | --- | --- |
| `tool_user_error` | 14 | 約 8.6〜10 秒 | 実行時間のほとんどが、ナレッジベースの検索ツール (`execute_tool mcp_FoundryIQ.knowledge_base_retrieve`、約 8〜9 秒。ツールのスパンは `success = true`) |
| `rate_limit_exceeded` | 3 | 約 0.5〜1.4 ミリ秒 | 子スパンなし。すぐ失敗 |

- 非同期 8 本をまとめて送った回は、`tool_user_error` が 6 本、`rate_limit_exceeded` が 2 本。A2A の応答は、8 本とも `failed` で、理由は付いていない。
- A2A の応答との対応 (APIM の再試行で、同じリクエストが 002、001 の順に失敗した 2 組で確認):

  | 回 | A2A の応答 (`error.message`) | スパンの `error.type` | かかった時間 |
  | --- | --- | --- | --- |
  | 1 回目 (002) | `-32099` "The tool request could not be completed. Check the tool configuration and input." | `tool_user_error` | 約 9.3 秒 |
  | 2 回目 (001) | `-32099` "The downstream request was rate limited." | `rate_limit_exceeded` | 約 1.1〜1.4 ミリ秒 |

  時刻とパターンの一致で対応させた (タイムスタンプには、数秒のずれがあった)。
- **`rate_limit_exceeded` が約 1 ミリ秒で返る**のは、モデルを呼ぶ時間にもならない速さで、**待ちを伴う再試行はしていない**とみられる。ハーネス版は、同じレート制限を、5 回、約 31〜34 秒かけて再試行してから失敗する (5.1)。
- `tool_user_error` の約 9 秒の中で、ナレッジベース側が再試行しているかは、見えない (ツール側は成功扱いで、中身のスパンもない)。

## 6. `-32099` について

- A2A v1.0 仕様 (§5.4、§9.5) に、`-32099` の個別の定義はない (`-32010`〜`-32099` にも、個別の定義はない)。Microsoft Learn の Foundry の A2A のドキュメントにも、記載はなかった。
- 実機では、Foundry が `-32099` を独自のエラーに使い、**原因を `reason` (v1.0 の `error.data[0]`) / `data.code` (v0.3) で区別**しているとみられる。今回確認できたのは次の2つ。

| 原因 | v1.0 の `reason` | v0.3 の `data.code` | `error.message` |
| --- | --- | --- | --- |
| ツールの失敗 (ナレッジベースのモデルのレート制限と整理。2.2) | `TOOL_USER_ERROR` | `ToolUserError` | The tool request could not be completed. Check the tool configuration and input. |
| ダウンストリームのレート制限 (エージェント自身のモデル。5.4) | `RATE_LIMIT_EXCEEDED` | `RateLimitExceeded` | The downstream request was rate limited. |

- 2 行目は、APIM 経由で記録された `error.message` と、スパンの `error.type` (`rate_limit_exceeded`) の対応で確認した (5.4)。`reason` と `data.code` の値は、APIM の記録には残っておらず、別の実行の応答で見たもの。

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
- Foundry 側 (`responsesapi`) の `invoke_agent github-copilot-preview-…` スパンの親スパン (4.6)。
- サブエージェント (`invoke_agent general-purpose`) が使われる条件 (12 回中 1 回だった。4.6)。
- 失敗した実行で、`execute_tool …knowledge_base_retrieve` が `success = false` になった原因 (5.1)。
- 通常のエージェントの `tool_user_error` (約 9 秒) の内訳。ナレッジベース側で再試行しているか (5.4)。
- `-32099` の `reason` の公式の一覧。
- 容量を戻した直後に出た `TOOL_USER_ERROR` が、変更の反映の遅れによるものか。
- ハーネス版の `artifacts` が2件になる理由の裏付け (Responses API の `output` の項目との対応と、サブエージェントが動いた回の件数は、確認していない)。

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
