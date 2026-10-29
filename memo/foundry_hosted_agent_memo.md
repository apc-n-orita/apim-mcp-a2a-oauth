# 調査メモ: Microsoft Foundry のホステッドエージェントと、長時間実行のレジリエンス

調査日: 2026-10-29
情報源: Microsoft Learn と、Foundry の開発者ブログ (参考は末尾)。**プレビューを含む情報で、変わる可能性がある。** この文書の内容は、ドキュメントの読み取りに基づき、実際にホステッドエージェントを動かして確認したものではない。
結論: **ホステッドエージェントは、自分のコード (任意のフレームワーク) をコンテナで持ち込み、ホスティング (ID、エンドポイント、スケール、セッション状態、観測) を Foundry に任せる方式。長時間実行のレジリエンスは、プロセスが止まっても (クラッシュ、メモリ不足、再デプロイ、スケールイン)、作業を引き継げるようにする仕組みだが、「ハンドラーが最初から再実行される」もので、進捗の保存と重複の防止は、アプリ側の責任。** ブログは GA と書くが、Learn の該当ページはプレビュー表記 (2.1)。

## 1. ホステッドエージェントとは

- エージェントを**コンテナイメージ**にして、Azure Container Registry に置く。デプロイすると、Agent Service がイメージを取得し、専用の Entra ID (エージェント ID) と、専用のエンドポイントを割り当てる。
- ホステッドエージェントは、Foundry のモデルカタログのモデルを推論に使い、オーケストレーションは、自分のコードが担う。
- プラットフォームが担当するもの: エンドポイント、ID、スケール、セッション状態の永続化、観測、ライフサイクル。**自分が担当するもの: サンドボックス内で動くコード。**

### 1.1 プロンプトエージェントよりホステッドを選ぶ場合

1. 自分のコードを持ち込みたい (Agent Framework、LangGraph、Semantic Kernel、独自コードなど)。
2. 独自のプロトコルを使いたい (Invocations で、Webhook や、OpenAI 形式以外のペイロード)。
3. サンドボックスの CPU とメモリを制御したい。
4. 状態を持つ処理を動かしたい (`$HOME` と `/files` エンドポイントで、ターンをまたいでファイルと状態を保持)。
5. 長く動く処理を、止まっても引き継げるようにしたい (長時間実行のレジリエンス)。

### 1.2 プロトコル

| プロトコル | 向いている場合 | 履歴 | ストリーミング | 長時間実行 |
| --- | --- | --- | --- | --- |
| **Responses** | ほとんどのエージェント。OpenAI 互換の `/responses` | プラットフォームが会話 ID で管理 | プラットフォームが管理 (`ResponseEventStream`) | バックグラウンドモードとポーリング。保存されたバックグラウンドのレスポンスには、任意で復旧 |
| **Invocations** | HTTP を完全に制御したい、独自のペイロード、長時間の非同期処理 | 自分で管理 (メモリ、Cosmos DB など) | 生の SSE。自分で形式を書く | AgentServer SDK の resilient task。ポーリングやストリームのエンドポイントは、自分で定義 |
| Activity | Teams と Microsoft 365 のチャネル連携 | — | — | Responses のロジックを Teams などに公開すると、自動で橋渡しされる |
| A2A | エージェント間の委任 | — | — | — |

- 1つのエージェントで、複数のプロトコルを組み合わせられる。迷ったら、Responses から始める。
- プロトコルのアダプターは、AgentServer Core の、resilient task とストリーミングのプリミティブと組み合わせて使う。

## 2. 長時間実行のレジリエンス

長時間動くホステッドエージェントは、開始したリクエストが切断されても、動き続けられる。また、ホスティングのプロセスが予期せず止まっても、復旧できる。

### 2.1 提供状況 (食い違いあり)

- **ブログ**: ホステッドエージェントの長時間実行のレジリエンスが **GA**。
- **Learn の該当ページ**: 「(preview)」の表記と、「Long-running agents are in preview. APIs and package versions are subject to change.」の注記がある。
- どちらが現在の状態かは、確認できていない。**本番で使う前に、最新の状態を確認する。**

### 2.2 バックグラウンド実行と、レジリエンスの違い

| 機能 | 提供するもの | 提供しないもの |
| --- | --- | --- |
| バックグラウンド実行 | クライアントがポーリングや再接続できる、非同期の処理 | 処理を持つプロセスが止まった後の復旧 |
| レジリエントな実行 | 作業の識別子、入力の永続化、プロセス消失の検知、ハンドラーの再入場 | すべての中間状態や副作用の、自動での保存 |
| ストリームの再生 | カーソルから、イベントを再生する (再接続したクライアント向け) | エージェント内部のワークフロー状態のチェックポイント |

### 2.3 仕組み

- 作業には、2つの識別子がある: **work identity** (論理的なジョブや、複数ターンの会話) と、**input identity** (その中の1つの入力やターン)。
- ハンドラーが始まる前に、ランタイムが入力を永続化し、作業のレコードの**リース**を取る。実行中は、リースを更新する。
- プロセスが止まってリースが放棄されると、別のプロセスが、同じ識別子と入力で、ハンドラーを再起動する。
- **復旧は、ハンドラーを最初から再入場させる。** 決定論的な再生ではなく、ローカル変数やコールスタックは復元されない。ハンドラーは、チェックポイントやウォーターマークで、どこまで終わったかを判断する。
- **再試行 (retry) とは別物**。再試行は、動いているハンドラーが報告した失敗への対応で、再試行の予算を消費する。復旧は、プロセスが消えた後に、同じ試行を続けるもので、予算を消費せず、実時間のタイムアウトも、再起動ではリセットされない。
- 作業の形:
  - **1回限りの作業**: 1つの入力が1つの結果を作る。同じ work identity での呼び出しは、重複実行されず、同じ論理操作にまとまる。
  - **複数ターンの連鎖**: 会話やセッションが、複数の入力を、順番に受ける。アプリが削除するか、保持期間が切れるまで、1つの work identity が続く。**steering** (任意) は、新しいターンを待たせ、現在のハンドラーに、早めに終えるよう合図する。

### 2.4 プラットフォームとアプリの責任

| Foundry と AgentServer SDK が提供 | アプリが提供 |
| --- | --- |
| 作業と入力の識別子 | 業務に対応する、安定した識別子 |
| ハンドラー実行前の入力の永続化 | タスクのペイロードの上限に収まる入力 (大きなデータは外部に) |
| リースによる、プロセス消失の検知とハンドラーの再入場 | 安全に再実行できる経路、または、永続した進捗から再開する分岐 |
| 小さな永続メタデータ | チェックポイントの参照、冪等性キー、副作用のウォーターマーク |
| 会話のロックと、steering のキュー | キュー、拒否、中断、キャンセルされたターンの、利用者から見える挙動 |
| イベントの保持と、カーソルによる再生 | ターンごとのストリーム ID、再接続に対応したクライアント |
| 終了または期限切れのレコードの掃除 | 外部のチェックポイント、セッション、アプリのデータの掃除 |

### 2.5 有効にする方法

**復旧は、既定ではオフ。** 明示的に有効にする。

- **Responses プロトコル**: `ResponsesAgentServerHost(options=ResponsesServerOptions(resilient_background=True))`。
  - 対象は、**`store=true` かつ `background=true`** のレスポンスだけ。
  - オフのままだと、クラッシュしたバックグラウンドのレスポンスは、`failed` (`error.code="server_error"`) になり、ハンドラーは再起動されない。
  - フォアグラウンド (`background=false`) のレスポンスは、常に `failed` になる (クライアントの接続が、すでにないため)。
- **Invocations / タスクのプリミティブ**: ホストの起動前に、`set_resilient_tasks_enabled(True)` を呼ぶ。`@task` を宣言するだけでは、有効にならない。

有効にすると、次のものは、ハンドラーを変更せずに得られる: ハンドラーの再起動 (同じリクエスト、入力、メタデータ)、永続化された SSE イベントの再生、会話のロック (競合する書き込みの防止)、復旧できないレスポンスを `failed` にする (黙って再実行しない)。**何もしなくても、再起動後のハンドラーは、正しい結果を作る (ターン全体を再実行する)。** 「どこから再開するか」は、必要なときに、ハンドラー側で実装する。

### 2.6 ハンドラーでの実装

**復旧後の再入場を検知する**

```python
@app.response_handler
async def handler(request, context, cancellation_signal):
    if context.is_recovery:
        stream = ResponseEventStream.from_snapshot(context.persisted_response)
        start_phase = len(stream.response.output)   # 完了済み (チェックポイント済み) の工程
    else:
        stream = ResponseEventStream(response_id=context.response_id, request=request)
        start_phase = 0
```

```python
@multi_turn_task(name="research")
async def research(ctx: TaskContext[dict]) -> dict:
    last_done = ctx.metadata.get("last_done_step", 0) if ctx.entry_mode == "recovered" else 0
```

`ctx.entry_mode` は、`fresh`、`resumed` (連鎖の次のターン)、`recovered` (前回が終わらず、永続した入力で再入場) のいずれか。

**再開の戦略**

| 戦略 | 進捗の場所 | 復旧時の挙動 |
| --- | --- | --- |
| 単純な再実行 | なし | ターン全体を再実行する。冪等でない副作用は、保護が必要 |
| フレームワークのチェックポイント | 永続化されたレスポンスのスナップショット | `context.persisted_response` から、チェックポイント済みの出力の続きを再開 |
| 上流が持つ再開 | フレームワークやアプリのストア | Agent Framework のチェックポイントや、自前のデータベースから再構築 |
| ウォーターマークの重ね合わせ | 小さなメタデータ | 上のどれとも組み合わせて、上流が重複排除できない副作用の繰り返しを防ぐ |

工程の区切りは、きれいにチェックポイントできる位置にする (工程ごとに、出力項目を1つ完了させてから、チェックポイントする)。チェックポイント前にクラッシュした工程は、再実行され、後なら、スキップされる。

**副作用の保護 (ウォーターマーク)**

取り消せない処理 (メール送信、課金など) の前に、ウォーターマークを永続化し、コミット後に消す。

```python
context.conversation_chain_metadata["email_sent"] = True
await context.conversation_chain_metadata.flush()   # 副作用の前に永続化
await email_service.send(...)
```

- クラッシュのタイミングで、結果が変わる: 目印を立てる前なら、送る (正しい)。立てた後、送信前なら、スキップされて**送られない**。送信後なら、スキップ (正しい)。つまり、**二重実行は防げるが、「実行されない」可能性が残る (最大1回の実行)**。
- 補う方法: 「開始」と「完了」の2段階にして、「開始済みで未完了」なら、相手側で、送信済みかを確認してから再実行する。相手のサービスの冪等性キーを使う (可能なら、これを優先する)。副作用が重要でないなら、単純な再実行でよい。

**グレースフルシャットダウン**

終了を待つ間に終えられないハンドラーは、終端状態を書かずに、復旧に回す。

```python
if context.is_shutting_down:      # タスクでは ctx.shutdown.is_set()
    await context.exit_for_recovery()   # in_progress のまま残し、次の起動で再入場させる
```

キャンセルとシャットダウンは、協調的 (ランタイムが合図し、ハンドラーが判断する)。

### 2.7 状態の保存 (FoundryStateStore)

進捗やチェックポイントが大きい、複数の工程にまたがる、フレームワークを使う、という場合は、外部に保存する。

| 保存先 | 向いているもの |
| --- | --- |
| **FoundryStateStore** (サーバー側の永続キーバリュー) | 進捗マーカーと、1 MB 以下のチェックポイント |
| エージェントフレームワークのチェックポインター | グラフの状態、human-in-the-loop の一時停止 |
| 自前のストレージ (Cosmos DB、Blob など) | 大きな入力や成果物、外部システムの状態 |

- 進捗マーカー (次にやる工程) と、チェックポイント (完了した工程の結果) を、別のアイテムにする。
- **チェックポイントを先に書いてから、進捗マーカーを進める。** 間でクラッシュしても、決まったキーで、完了済みと判断できる。
- 進捗マーカーは、ETag (`if_match`) で更新する。チェックポイントは、決まった追記専用のキーで `create_item()` する (競合する書き込みで上書きされない)。409 や 412 が返ったら、読み直して、既存のチェックポイントと整合させてから再試行する。
- `get_or_create()` は、`user_isolation` と `item_ttl_seconds` を、最初の作成時にだけ適用する。ストア名が範囲 (ワークフロー、セッション、実行など) を表す (`/` で階層にできる)。
- 制限: 1アイテムは最大 1 MB (JSON)。ストア名は 1〜128 文字。アイテムのタグは 16 個まで。
- メタデータには、チェックポイントの ID、最後に完了した工程、外部データへのポインターなどの**小さな値**だけを入れる (チェックポイントのストアにしない)。

### 2.8 ストリームの再生

- **ターンごとのストリーム ID** を使う (複数ターンの会話の ID を、ストリーム ID にしない)。
- 保存先 (Invocations とタスクのプリミティブでは、起動時に1つ選ぶ):

| 保存先 | 遅れて接続・再接続した購読者への再生 | プロセスの再起動を超える |
| --- | --- | --- |
| `use_in_memory_live()` (既定) | なし | なし |
| `use_in_memory_replay(...)` | `ttl_seconds` の間は可 | なし |
| `use_file_backed_replay(...)` | 可 | 可 |

- カーソルによる再接続には、`cursor_fn` (イベントから、単調増加の整数を返す) が必要。渡さないと、`subscribe(after=...)` は無視される。
- 復旧した Responses のストリームでは、後で届く `response.in_progress` が**スナップショットのリセット**になる。クライアントは、それまでに溜めた出力を、そのスナップショットで置き換え、スナップショットにない部分的な出力を捨ててから、続くイベントを適用する。出力のインデックスは、復旧の試行をまたいで、増加するとは限らない。

### 2.9 設計の境界

レジリエントなタスクは、決定論的な再生、ワークフローのオーケストレーション、大量のデータの保存を、提供しない。次と組み合わせる。

1. グラフの状態や、human-in-the-loop の一時停止には、エージェントフレームワークのチェックポインター。
2. ファンアウト/ファンイン、永続タイマー、子ワークフローには、ワークフローエンジン。
3. 大きな入力、生成した成果物、外部の状態には、アプリのストレージ。
4. 下流のサービスの冪等性のサポートを、可能なら使う。

ハンドラーは、どの時点で処理が失われても、「安全に再実行される」か、「永続した状態から、正確な境界で再開する」のどちらかになるように設計する。

### 2.10 A2A との関係

- A2A は、ホステッドエージェントの対応プロトコルの1つとして挙げられている (他のプロトコルと組み合わせられる)。
- **ただし、レジリエンス (クラッシュ後の復旧) が、A2A に対応していない可能性がある。** Learn のレジリエンスの記述が対象にしているのは、Responses (`resilient_background`) と Invocations (resilient task) だけで、A2A についての記述が見つからなかった。
- A2A で復旧が動くかどうかは、動作確認をしておらず、公式にも対応と書かれていない。

## 3. ホステッドエージェントで、GitHub Copilot SDK を使う例

- 公式のサンプル (`foundry-samples` の `samples/python/hosted-agents/bring-your-own/invocations/github-copilot`) がある。エージェントのコードの中で、`CopilotClient` を使い、`skills/<名前>/SKILL.md` を `skill_directories` で読み込む。セッション開始時に、追加の指示として注入される。
- **これは、プロンプトエージェント向けの Microsoft Copilot harness とは別物。** ハーネスは、プロンプトエージェント向けのオプションのランタイムで、ホステッドエージェントには使えない (ホステッドは、ハーネスなしで、自分でランタイムを持つ方式として、対比されている)。
- 必要なもの: GitHub の **fine-grained PAT** (権限は、Copilot requests: Read-only)。classic トークン (`ghp_`) は非対応。安全な保管先に置き、コミットやログ出力をせず、有効期限を短くする。
- 手順 (サンプルより): `azd ai agent init -t <サンプルの azure.yaml の URL>`、`azd env set GITHUB_TOKEN=<PAT>`、ローカル実行 `azd ai agent run` と `azd ai agent invoke --local '{"input": "…"}'`、`azd provision` と `azd deploy`、リモート `azd ai agent invoke '{"input": "…"}'`。

### 3.1 スキルの使い方 (ホステッド)

| 方式 | 内容 |
| --- | --- |
| 直接の注入 | Foundry のスキル API から、スキルをダウンロードして、プロジェクトに同梱する (`skills/<名前>/SKILL.md`)。エージェントが起動時に読み、各セッションの追加の指示にする。特定のバージョンを、コードに同梱したいときに向く |
| Toolbox 経由 | スキルを Toolbox に付けて、MCP クライアントが、ツールと同じエンドポイントから発見する (MCP Resources の `resources/list`、`resources/read`)。Agent Framework では、`AgentSkillsProvider` (`UseMcpSkills`) で、名前と説明を先に載せ、必要なときに本文を読み込む |

## 4. プロンプトエージェント + Copilot harness との比較

| 観点 | ホステッドエージェント | プロンプトエージェント + Copilot harness (別メモ) |
| --- | --- | --- |
| ランタイム | 自分のコード (コンテナ) | Foundry が運用 |
| フレームワーク | 任意 | 選べない (設定のみ) |
| 運用の負担 | 大きい (イメージ、依存関係、デプロイ) | 小さい |
| CPU・メモリ | 指定できる | 設定できない |
| 長時間実行の復旧 | あり (レジリエンス) | 記述なし (ワークスペースは会話単位。永続は Foundry Files などに) |
| プロトコル | Responses、Invocations、Activity、A2A | Responses (A2A なども公開可) |
| Foundry Memory | 記述なし | 非対応 |
| 状況 | レジリエンスは、GA またはプレビュー (2.1) | パブリックプレビュー |

## 5. 前提条件 (クイックスタートより)

- 既存の Foundry プロジェクトを使うなら、プロジェクトスコープの **Foundry Project Manager** ロール。新しいプロジェクトを作るなら、リソースグループスコープの Owner ロール。
- Application Insights をプロジェクトに接続し、クラウドのトレースを読む権限を付ける (最初のリモート呼び出しの前に)。
- Foundry Dev Pack (Azure CLI、`azd`、Foundry Skill)。`azd` のホステッドエージェントのコマンドは、`azd ai agent …`。
- コーディングエージェント (GitHub Copilot、Claude Code など) から、Foundry Skill で、作成、デプロイ、評価、監視を進めることもできる。

## 6. 未確認のこと

- この文書は、ドキュメントの読み取りに基づく。ホステッドエージェントの作成、デプロイ、復旧の動作は、実際には試していない。
- レジリエンスが GA か、プレビューか (2.1)。
- A2A のプロトコルでの、クラッシュ復旧の扱い。
- タスクのペイロードの上限の具体的な値 (Learn に、値の記述が見つからなかった)。
- Responses のバックグラウンドの復旧で、実際に再起動したときの、再入場とスナップショットの挙動。

## 7. 参考

- [What are hosted agents?](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents)
- [Hosted agent runtime contract](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agent-contract)
- [Resilience for long-running hosted agents](https://learn.microsoft.com/azure/foundry/agents/concepts/long-running-agent-resilience)
- [Recover long-running work after a crash](https://learn.microsoft.com/azure/foundry/agents/how-to/recover-long-running-work)
- [Manage state for long-running agents](https://learn.microsoft.com/azure/foundry/agents/how-to/manage-task-state)
- [Stream long-running agent output with reconnect](https://learn.microsoft.com/azure/foundry/agents/how-to/stream-with-reconnect)
- [Use skills in Foundry](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/skills)
- [Quickstart: Deploy your first hosted agent](https://learn.microsoft.com/azure/foundry/agents/quickstarts/quickstart-hosted-agent)
- [Microsoft Copilot harness in Foundry (devblogs)](https://devblogs.microsoft.com/foundry/microsoft-copilot-harness-in-foundry/) (GA の記述)
- プロンプトエージェント向けのハーネス: [foundry_copilot_harness_memo.md](foundry_copilot_harness_memo.md)
