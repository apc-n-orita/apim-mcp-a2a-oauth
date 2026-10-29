# 調査メモ: Microsoft Foundry の Copilot harness (プロンプトエージェント向けのマネージドランタイム)

調査日: 2026-10-29
情報源: Microsoft Learn と、Foundry の開発者ブログ (参考は末尾)。**プレビューの情報で、変わる可能性がある。** 一部は、実際に作成して確認した (その箇所に明記)。
結論: **Copilot harness は、Foundry のプロンプトエージェントに、「複数ステップでツール・スキル・ファイル・コマンドを使う作業」をさせるための、Foundry が運用するランタイム (パブリックプレビュー)。コードのデプロイや運用は不要で、リソースは、引き続きプロンプトエージェントとして、Responses API で呼び出す。作成時にしか選べず、既存のエージェントには後から付けられない。**

## 1. 何のためのものか

- 従来のプロンプトエージェントは、「モデル、指示、ツール」を定義して呼び出す形だった。ファイルの読み書き、コマンドの実行、手順書 (スキル) に従った複数ツールの使い分け、といった作業をさせるには、エージェントのループ、実行環境 (サンドボックス)、コンテキスト管理を、自分で用意する必要があった。
- ハーネスは、これらを**マネージドで提供**する。モデルとツールの呼び出しを調整し、作業の途中経過 (コンテキスト) を管理し、設定された上限とポリシーの範囲で動かす。
- ブログでは、次の4つの要素で説明されている。
  - **再利用可能なスキル**: 指示、スクリプト、リソースをまとめた手順書。
  - **接続ツール**: 対応する Foundry のツールと MCP ツール。認証と承認は、明示的に設定する。
  - **実行と委任**: ファイルやコードの操作、組み込みのサブエージェントへの委任。
  - **ソース管理できるエージェント定義**: Foundry 上で作成・テストするか、アプリのコードと一緒に管理する。

### 1.1 位置づけ (使い分け)

| 選択肢                                       | 運用                  | 自由度          | 向いている場合                                                                                        |
| -------------------------------------------- | --------------------- | --------------- | ----------------------------------------------------------------------------------------------------- |
| 通常のプロンプトエージェント                 | Foundry 管理          | 低い            | 単純な応答や、少ないツール呼び出し                                                                    |
| **プロンプトエージェント + Copilot harness** | Foundry 管理          | 低い (設定のみ) | 複数ステップのツール、スキル、ファイル、コマンドの作業を、運用負荷なしで任せたい                      |
| ホステッドエージェント                       | 自分で管理 (コンテナ) | 高い            | フレームワーク、オーケストレーション、ミドルウェア、依存関係、プロセスモデルを自分で持ちたい (別メモ) |

### 1.2 混同しやすいもの

- **Copilot Studio の「GitHub Copilot harness」**: Copilot Studio 側の、別のエージェントランタイム。Foundry、M365 SDK、A2A のエージェントを connected agent として接続できる、と説明されている。**この文書の対象 (Foundry のプロンプトエージェント向け) とは、別の製品の話。**
- **Foundry Canvas / Microsoft Foundry Skill**: GitHub Copilot アプリや、コーディングエージェント (Copilot、Claude Code など) から、Foundry のエージェント (主にホステッドエージェント) を作成・管理するための拡張。ハーネスそのものではない。
- GitHub Universe 2026 の発表内容との対応は、確認できていない (開催中で、発表の記事を確認できなかった)。

## 2. 提供状況と料金

- **パブリックプレビュー**。SLA はなく、本番利用は推奨されない。
- 料金 (ブログ): **2026年12月1日まで**は、ハーネスの実行は無料。**12月1日から**は、サンドボックスの計算資源とメモリの従量課金 (vCPU が $0.0994/時間、メモリが $0.0118/GiB 時間)。モデルの推論料金と、ツールや接続サービスの料金は、別にかかる。
- **対応リージョン**: Australia East、Canada Central、Central US、Germany West Central、Japan East、Sweden Central、UK South、West Europe、West US。
  - 対応外のリージョン (eastus など) で作成すると、403 `forbidden` ("… is not enabled for this subscription") になった (実際に確認した。原因がリージョンかどうかは、エラーメッセージからは確定できない)。
- **モデル**: reasoning とツール呼び出しに対応したモデル。BYOM (自分のモデルの持ち込み) は非対応。

## 3. 機能

### 3.1 組み込みのハーネスツール (5種)

新規のエージェントでは、すべて有効。

| ツール            | 設定名             | できること                                   |
| ----------------- | ------------------ | -------------------------------------------- |
| File system read  | `filesystem_read`  | ワークスペース内のファイルの読み取り、検索   |
| File system write | `filesystem_write` | ワークスペース内のファイルの作成、変更       |
| Shell             | `shell`            | OS コマンドの実行                            |
| Web               | `web`              | URL から Web コンテンツを取得 (検索ではない) |
| Subagents         | `subagents`        | 別のエージェントへの作業の委任               |

- 設定は、プロンプトエージェントの `tools` に、`microsoft_copilot_toolset_preview` を**1つだけ**入れる。`defaultConfig.enabled: false` にして、必要なものだけを有効にする「許可リスト方式」もできる。名前の重複や不明な名前は、エージェントバージョンの作成が失敗する。
- **Shell が最も強力**。ファイルの読み書きやネットワークアクセスができるため、他のツールを無効にしても、シェルが有効なら、厳密なセキュリティ境界にはならない。別途宣言したシェルや Code Interpreter も、この設定とは独立。
- プレビュー中、ハーネスツールの承認ポリシーは、サービスが管理する。`require_approval` が効くのは、自分で設定した MCP ツールだけ。

### 3.2 スキル

- **形式**: `SKILL.md` を含むフォルダ (オープンな Agent Skills 形式)。スクリプトや参考資料も同梱できる。front matter の `name` (小文字・数字・ハイフン、64文字以内、引用符なし) と `description` (1,024文字以内) が必須。
- **バージョン管理**: 更新ごとに、不変のバージョンができ、`default_version` を切り替えるだけで、ロールバックできる。
- **エージェントへの付け方**:
  1. プロンプトエージェントから直接参照する (最大50件。同じプロジェクトのスキル)。
  2. Toolbox に付ける。MCP Resources 経由で、MCP クライアントが発見する (SEP-2640、プレビュー)。ハーネスも、互換性のある Toolbox に付いたスキルを発見できる。
  3. ホステッドエージェントに、ダウンロードして同梱する (別メモ)。
- **段階的開示**: 最初は名前と説明だけをプロンプトに載せ、必要になったときに、本文や資料を読み込む。トークンの節約になる。
- 作成方法: REST (`POST …/skills/{name}/versions`、ヘッダー `Foundry-Features: Skills=V1Preview`)、Python / .NET / JS の SDK、`azd ai skill`、VS Code の拡張。VS Code の Tool Catalog には、既成のスキル (`docx`、`pptx`、`xlsx`、`pdf` など) がある。

### 3.3 ツール連携

- **Foundry web search**: プロジェクト接続が不要。ハーネスの `web` (URL 取得) とは別。
- **Function tools**: アプリ側で実行する。`strict: true` は非対応。関数名に予約の区切り `___` は使えず、ハーネスのツール名と重複できない。
- **MCP ツール**: プロジェクト接続経由で使う。`require_approval` で承認制にできる。
- **Toolbox**: 共有のツール群を付ける。対応するツールは、Toolbox の feature support の表を参照。

### 3.4 実行環境

- **会話ごとに、独立したワークスペース**と、Foundry 管理のサンドボックスがある。サンドボックスは、アイドル、再開、入れ替えが自動で行われ、CPU とメモリは設定できない。
- ワークスペースは**作業用の一時領域**で、重要な出力は、Foundry Files などの永続先に保存する必要がある。
- **入力ファイル**は、ワークスペースに自動で置かれる (ベストエフォート。無効なファイル ID、大きすぎるファイル、一時的な取得の失敗では、スキップされ、テキストの部分だけが処理される)。
- **生成ファイル**は、Foundry Files に自動でアップロードされる。エージェント ID (`instance_identity.principal_id`) に、プロジェクトスコープの Foundry User ロールが必要で、反映に最大5分かかる。

### 3.5 ガバナンス

- **ネットワーク egress 制御 (プレビュー)**: RAI ポリシーの Network ルールで、ハーネス環境からの直接送信を、ホスト (FQDN) で Allow / Deny する。Audit (ログのみ) と Enforce (HTTP 403 で遮断) がある。対象は、シェルやハーネスの `web` からの直接通信で、Code Interpreter や web search など、宣言された Foundry ツールは、別の境界になる。稼働中の環境は、ポリシーの変更を再読み込みしないので、新しい会話で確認する。
- MCP ツールの承認 (`require_approval`) と `mcp_approval_request` / `mcp_approval_response`。
- Entra ID、マネージド ID、OAuth を使い、資格情報を、指示、スキル、ファイルに埋め込まない。スキルは、コードとして扱い、レビューしてバージョンを固定する。

## 4. 作り方

共通の前提: 対応リージョンのプロジェクト、reasoning とツール呼び出しに対応したモデルのデプロイ、プロジェクトの Foundry User ロール。接続を作るには Foundry Project Manager ロール。ハーネスの選択は、**エージェントの作成時だけ**で、既存のエージェントに後から付けられず、別のバージョンを作っても変わらない。

| 方法                | 要点                                                                                                                                                                                                                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ポータル            | New Foundry をオンにし、対応リージョンのプロジェクトで、**Build an agent** → **Create an agent** → 名前 → Text → **Use the Microsoft Copilot harness** → **Create**。設定を変えたら、**Save and start new chat** で、新しいバージョンが有効になるのを待つ                 |
| azd                 | azd 1.37.0 以降、`azure.ai.agents` 1.0.0-beta.22 以降、環境変数 `AZD_ALPHA_ENABLE_AGENTS_MANAGED_HARNESS=true`。`azure.yaml` の `azure.ai.agent` に `harness: { type: microsoft_copilot_preview }`。スキルは `azure.ai.skill` として宣言して、`skills` と `uses` に入れる |
| SDK                 | Python は `azure-ai-projects>=2.9.0`、`PromptAgentDefinition(..., harness=MicrosoftCopilotHarness())`、`allow_preview=True`。C# は `Azure.AI.Projects.Agents` 3.0.0-beta.5、TypeScript は `@azure/ai-projects` 2.9.0 (Node.js 22 以降)、Java は `azure-ai-agents` 2.8.0   |
| REST (実際に使った) | `POST <project>/agents/<name>/versions?api-version=v1`、ヘッダー `Foundry-Features: MicrosoftCopilot=V1Preview` (スキルを使うなら `,Skills=V1Preview`)。`definition` に `harness: { type: "microsoft_copilot_preview" }` を入れる                                         |

`definition` の例 (実際に作成して、動作を確認したもの):

```json
{
  "kind": "prompt",
  "model": "<モデルのデプロイ名>",
  "reasoning": { "effort": "low" },
  "instructions": "<短い指示。詳細はスキルに書く>",
  "harness": { "type": "microsoft_copilot_preview" },
  "tools": [
    {
      "type": "mcp",
      "server_label": "<ラベル>",
      "server_url": "<MCP の URL>",
      "project_connection_id": "<接続名>",
      "allowed_tools": { "tool_names": ["<ツール名>"] },
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
    { "type": "skill_reference", "name": "<スキル名>", "version": "1" }
  ]
}
```

- 作成後の定義では、`skills` は `{ "name": …, "version": … }` の形で保存された。
- A2A を有効にするには、`PATCH <project>/agents/<name>?api-version=v1` で、`agent_card` と `agent_endpoint.protocol_configuration` (`responses` と `a2a`) を設定する (下の 6 章)。

### 4.1 呼び出し

- Responses API で呼ぶ。**各リクエストに、会話が必要**。`store` は省略するか `true`。`previous_response_id` は使わず、同じ会話で次のリクエストを送る。
- 設定 (モデル、指示、ツール、スキル) を変えて、新しいバージョンを作ったとき、**新しい会話は、すぐに選択中のバージョンを使う**。稼働中の環境は再起動されず、初期化済みの機能は、前のバージョンを使い続けることがある。アイドル後の次のやり取りで、選択中のバージョンに入れ替わる。クリーンな境界が必要なら、新しい会話を始める。

## 5. 制約

- 作成時にしか選べない (既存のエージェントには付けられない)。
- BYOM は非対応。**Foundry Memory は非対応** (会話の履歴と、ワークスペースのファイルは別で、影響しない)。
- 対応リージョンが限られる (2 章)。
- スキルは最大50件。名前は一意で、小文字・数字・ハイフン、64文字以内。
- Function tools は、`strict: true` が非対応。
- ワークスペースは、会話単位。サンドボックスの CPU とメモリは設定できない。
- 未対応のフィールドや操作は、**無視されずにエラー**になる。

## 6. A2A との関係 (実際に確認したこと)

- **ハーネス版のエージェントを、A2A のエンドポイントとして公開し、呼べる** (受信 A2A は、Responses プロトコルが必要で、ハーネス版のエージェントもこれを満たす)。エージェントカード (v1.0 と v0.3)、同期、非同期の呼び出しが動いた。
- 挙動は、通常のプロンプトエージェントと違う点がある (詳細は、`a2a_sync_async_failover_experiment_memo.md`)。
  - 非同期で最初に返る状態が、`working` (通常は `submitted`)。
  - **失敗が、同期及び非同期でも、JSON-RPC の `error` ではなく、`failed` のタスクで返り、理由が付かない。**
  - 回答のアーティファクトが、前置き + 回答の1〜2件になる。
- ハーネス版のエージェントが、A2A ツールで外部のエージェントを呼ぶ方向は、確認していない。

## 7. 実際に動かして見たこと (ログ)

- スキルを付けたエージェントの1回の実行で、モデル呼び出し (`chat`) の間に、`execute_tool skill` (スキルの読み込み)、`execute_tool …knowledge_base_retrieve` (MCP ツール) が順番に実行された。スキルの指示どおり、ツールが呼ばれた。
- ハーネスのファイル読み取りツール (`view`) が、失敗することがあった (理由は未確認)。
- 起動時に、`Managed Toolbox manifest could not be primed; continuing with Copilot-only priming` (Warning、Toolbox を使っていない場合も出る)、`Hook handler failed` (RuntimeError) などが `exceptions` に記録された。これらの `type` が `JsonRpcError` になるものがあり、他の用途の同名の例外 (KQL の絞り込み) と混ざる点に注意。
- レート制限の間、ハーネス内で、モデル呼び出しが約1秒ごとに 500 で失敗して再試行され、30〜45秒ほどで諦めて `failed` になるように見えた (別構成のエージェントで確認)。

## 8. 参考

- [Use the Microsoft Copilot harness with prompt agents](https://learn.microsoft.com/azure/foundry/agents/how-to/use-tools-skills-copilot-harness)
- [Foundry Agent Service limits, quotas, and regional support (Microsoft Copilot harness)](https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions#microsoft-copilot-harness-preview)
- [Foundry Agent Service FAQ](https://learn.microsoft.com/azure/foundry/agents/faq)
- [Use skills in Foundry](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/skills)
- [Create and manage a toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [Microsoft Copilot harness in Foundry (devblogs)](https://devblogs.microsoft.com/foundry/microsoft-copilot-harness-in-foundry/)
- [Agents powered by the GitHub Copilot Harness overview (Copilot Studio。別製品)](https://learn.microsoft.com/microsoft-copilot-studio/agents-experience/overview)
- [What is Microsoft Foundry Canvas?](https://learn.microsoft.com/azure/foundry/agents/concepts/foundry-canvas)
- A2A の挙動の実験: [a2a_sync_async_failover_experiment_memo.md](a2a_sync_async_failover_experiment_memo.md)
