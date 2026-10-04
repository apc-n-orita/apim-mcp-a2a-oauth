# 実験メモ: トレースのサンプリング 0% で、例外ログとメトリックは落ちるか

実施日: 2026-10-04
対象: `src/foundryiq-acl-mcp` (Azure Functions の MCP ツール。Python、`azure-monitor-opentelemetry` 1.8.6)
結論: **トレースのサンプリングを 0% にしても、`_logger.exception` の例外ログも、トークン量のメトリックも落ちなかった。**
(実験は小規模で、例外 3 件、検索 3 回。傾向の確認であり、統計的な保証ではない)

## 1. 背景

### 1.1 懸念 (Reddit のスレッド)

https://www.reddit.com/r/dotnet/comments/1lrm56k/azure_monitor_opentelemetry_exception_sampling/

- .NET の Azure Monitor OpenTelemetry で、`ILogger.LogError(例外, ...)` のように例外つきで出したログは、`traces` テーブルではなく `exceptions` テーブルに入る。
- トレースはサンプリングされるため、例外が `exceptions` として、サンプリングの対象になると、重要な情報を失うかもしれない。
- コメントでは、「例外だけサンプリングを外すことはできない」「ミドルウェアで、例外を、メッセージだけの `LogError` で出す」などの回避策が出ていた。

### 1.2 このアプリでの論点

1. Python でも、例外つきのログは `exceptions` テーブルに入る (エクスポーターのソースで確認: ログレコードに `exception.type` などがあると、例外のエンベロープになる)。
2. では、トレースのサンプリングで、その例外ログも落ちるのか。
3. また、トークン量のメトリック (課金に関わる合計) は、サンプリングの影響を受けないのか。

### 1.3 事前に分かっていたこと (Learn とソース)

- サンプリングの判断は、トレース (スパン) に対して行われる。メトリックはサンプリングされない。
- Python では、`enable_trace_based_sampling_for_logs` の既定は `False` (1.8.6 と、最新の 1.8.10 のソースで確認)。`True` のときだけ、サンプリングされなかったトレースに属するログが落ちる。
- このアプリは、`telemetry.py` で `enable_trace_based_sampling_for_logs=False` を、既定値と同じ値で、明示している (バージョンの変化に備えるため)。
- `telemetryMode` が `OpenTelemetry` のとき、`host.json` の `logging.applicationInsights.samplingSettings` (例: `excludedTypes: "Exception"`) は効かない (Learn に明記)。

## 2. 実験の設計

### 2.1 サンプラーの設定値の選び方

`OTEL_TRACES_SAMPLER` の値は、ディストロの設定の処理 (`_utils/configurations.py`) が認識する次の 8 つのいずれか。これ以外だと、エラーをログに出して、既定のレート制限付き (5 トレース/秒) にフォールバックする。
`microsoft.rate_limited`、`microsoft.fixed_percentage`、`always_on`、`always_off`、`trace_id_ratio`、`parentbased_always_on`、`parentbased_always_off`、`parentbased_trace_id_ratio`。

選んだ値: **`OTEL_TRACES_SAMPLER=microsoft.fixed_percentage`、`OTEL_TRACES_SAMPLER_ARG=0`**

理由:

- `parentbased_*` は、上流 (APIM) のサンプリングの判断を引き継ぐ。上流が「サンプリングする」と判断してくると、こちらが 0 でも記録されてしまい、実験が成立しない。
- `microsoft.fixed_percentage` は、上流の判断に関係なく、独立して判断する (Learn の FAQ)。引数の `0` は有効 (範囲は 0.0〜1.0)。`ApplicationInsightsSampler` は、サンプル率が 0 のとき、常に DROP する (ソースで確認)。
- `always_off` は避けた。ディストロには、種類を見ず、`OTEL_TRACES_SAMPLER_ARG` の数値だけでサンプラーを作る、別の経路 (自動計装の `configurator.py`) がある。この経路では、`always_off` を引数なしで指定すると、1.0 (全件) 扱いになり、実験が無効になる。`microsoft.fixed_percentage` ＋ `0` は、どちらの経路でも 0% になる。

### 2.2 変更した設定 (実験中のみ)

| 設定                      | 通常                         | 実験 1 (例外)                           | 実験 2 (メトリック)  |
| ------------------------- | ---------------------------- | --------------------------------------- | -------------------- |
| `OTEL_TRACES_SAMPLER`     | `parentbased_trace_id_ratio` | `microsoft.fixed_percentage`            | 同左                 |
| `OTEL_TRACES_SAMPLER_ARG` | `1`                          | `0`                                     | `0`                  |
| `KNOWLEDGE_BASE_NAME`     | 本来のナレッジベース         | 存在しない名前 (検索をわざと失敗させる) | 本来のナレッジベース |

変更は、Terraform (`infra/main.tf`) で行い、差分を見ながら、デプロイした。

### 2.3 成功の判定

- 実験 1: スパン (ツールのスパンと AI Search への依存関係) は落ちるのに、`_logger.exception` の例外が、`exceptions` テーブルに残る。
- 実験 2: スパンは落ちるのに、`customMetrics` に、トークン量のメトリックが、検索の回数ぶん記録される。

## 3. 実験 1: 例外ログ

### 3.1 手順

1. 上の設定 (実験 1) をデプロイ。
2. MCP の検索を 3 回実行。ナレッジベースが存在しないため、AI Search が 404 を返し、`foundryiq_knowledge_retrieve` が `_logger.exception("Knowledge retrieval failed.")` を出して、`Knowledge retrieval failed` を返す (3 回とも想定どおり)。
3. Application Insights で、`exceptions`、`dependencies`、`requests`、`traces` を確認。

### 3.2 結果

| 項目                                             | 結果                                                                                                                                                               |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `exceptions`                                     | **3 件、すべて記録**。型 `ResourceNotFoundError`、メッセージ `Knowledge retrieval failed.`、`operation_Id` つき                                                    |
| 例外の `customDimensions`                        | `tool`、`error_type`、`status_code=404`、`reason=Not Found`、`kb`、`api_version`、`acl_header_present`、`code.line.number` (`_logger.exception` の `extra` と一致) |
| ツールのスパン、AI Search の retrieve の依存関係 | **0 件** (3 回とも記録されず。0% が効いている)                                                                                                                     |
| Function 側の依存関係                            | `init` (InProc) 2 件のみ (ホスト側のもの)                                                                                                                          |
| `RetainedPercentage` (Function 側のロール)       | request / dependency / exception / trace のすべて 100% (`itemCount`=1)                                                                                             |

### 3.3 解釈

- **スパンは 0% で落ちているのに、同じ呼び出しの `_logger.exception` の例外は、3 回とも残った。**
- 例外は、スパンがないトレースに、`operation_Id` だけを引き継いで記録されている (APIM 側のリクエストと依存関係が、同じ `operation_Id` を持つ)。
- Python の既定 (`enable_trace_based_sampling_for_logs=False`) では、ログ経由の例外は、トレースのサンプリングに引きずられない。Reddit のスレッドの .NET のような問題は、この構成では起きていない。
- このアプリは、`knowledge_retrieve.py` で、例外を `_logger.exception` (ログ) として出し、`record_exception` (スパン側) を使っていない。スパンのイベントとして記録された例外は、スパンが落ちると一緒に失われるため、ログ側を正とする設計が、結果的に有効だった。

## 4. 実験 2: メトリック

### 4.1 手順

1. 実験 2 の設定 (サンプリング 0%、本来のナレッジベース) をデプロイ。
2. MCP の検索を 3 回実行 (3 回とも成功)。
3. `customMetrics` と、スパン (`dependencies`) を確認。

### 4.2 結果

| 項目                                             | 結果                       |
| ------------------------------------------------ | -------------------------- |
| ツールのスパン、AI Search の retrieve の依存関係 | **0 件** (0% が効いている) |
| `kb.llm_input_tokens`                            | 3031                       |
| `kb.llm_output_tokens`                           | 152                        |
| `kb.llm_total_tokens`                            | 3183 (3031 + 152 と一致)   |
| `kb.reasoning_tokens`                            | 204656                     |
| ディメンション                                   | `kb.name`                  |
| 検索の回数 (APIM 側の `POST .../mcp`)            | 3 回 (すべて 200)          |

### 4.3 解釈

- **スパンは 0% で落ちているのに、メトリックは落ちていない。**
- 値は、回数に見合っている。サンプリング 100% のときの 1 回あたりの実測 (LLM 合計 約 1,060〜1,075、reasoning 約 68,000〜70,000) の 3 倍が、LLM 合計 約 3,200、reasoning 約 204,000。
- 「メトリックはサンプリングされない」(Learn) が、このアプリで、実機でも確認できた。

## 5. 補足と未解明の点

### 5.1 メトリックの回数の判断

- 3 回の検索が、同じ 1 分の送信間隔に入ったため、メトリックは 1 つのデータポイント (`valueCount=1`) に集約された。`valueCount` は、`add()` を呼んだ回数ではなく、送信間隔ごとの集約ポイントの数なので、回数は、メトリックだけでは分からない。「3 回ぶん記録された」という判断は、次の 2 つを合わせて行った。
  1. **APIM 側のリクエスト数 (回数の根拠)**: APIM は 100% で記録されるので、実験中の呼び出し回数を、そのまま数えられる。実験 2 の開始時刻以降の、Function への MCP のリクエストが、ちょうど 3 件 (すべて 200)。MCP クライアントは、同じセッションを使い回していて、この時間帯の APIM 側には、ほかの MCP の呼び出しの記録はなかった。
     ```kusto
     requests
     | where timestamp > datetime(<開始時刻>)
     | where cloud_RoleName has "apim" and name has "foundryiq-acl-mcp"
     | project timestamp, name, resultCode
     ```
  2. **合計の大きさ (値の裏付け)**: サンプリング 100% のときに、スパン属性とメトリックの一致を確認した 1 回あたりの実測が、LLM 合計 1061 と 1075、reasoning 68131 と 70633。実験 2 の合計 (LLM 合計 3183、reasoning 204656) を 3 で割ると、1061 と 68219 で、その範囲に入る。1 回だけ、または 2 回だけなら、この大きさにはならない。
- 実験 2 では、スパンが落ちているため、「スパン属性の値とメトリックの値が一致する」ことは確認できない。これは、サンプリング 100% のとき、別に確認済み (入力 1011 / 出力 50 / 合計 1061 / reasoning 68131 が、スパン属性とメトリックで一致)。
### 5.2 Function 側の `requests` が少ない件

- Function 側の `requests` (`POST /runtime/webhooks/mcp`) は、実験 1 で 3 件、実験 2 で 1 件のみで、2 回目以降の呼び出しに対応するものが見当たらない。**原因は不明。** 結論には影響しない。
  - 参考データ (実施日の `POST` の MCP リクエストを、10 分ごとに、APIM 側 (100% で記録) と Function 側で比較):

    | 時間帯 (UTC) | APIM 側 | Function 側 | 状況 |
    |---|---|---|---|
    | 12:20 | 44 | 42 | サンプリング 100% |
    | 12:50 | 6 | 5 | サンプリング 100% |
    | 13:00 | 1 | 1 | サンプリング 100% |
    | 13:20 | 1 | 1 | サンプリング 100% |
    | 16:30 | 9 | 3 | 0% (実験 1) |
    | 17:30 | 3 | 1 | 0% (実験 2) |

    100% の間は、Function 側が APIM 側とほぼ 1 対 1 で記録されているが、0% の間 (実験 1、実験 2) だけ、Function 側が、APIM 側より少ない。
  - 実験 2 の Function 側の 1 件を詳しく調べた結果:
    - `operation_ParentId` と `operation_Id` が、APIM の **1 回目**の呼び出し (依存関係とリクエスト) と一致する。所要時間は約 10.0 秒 (1 回目はコールドスタートを含み、APIM 側は約 11.8 秒。2 回目、3 回目は約 4.4 秒と約 3.0 秒)。
    - `itemCount` は 1。0% の時間帯、100% の時間帯とも、Function 側の `requests` の `itemCount` の最大値は 1 (98 件対 98、4 件対 4) で、1 行が複数件を表している形跡はない。
    - 2 回目、3 回目の呼び出しに対応する Function 側の行は、存在しない。
    - つまり、「3 回が 1 行に集約された」のではなく、「**1 回目だけが記録され、2 回目、3 回目は記録されなかった**」というデータになっている。
  - `requests` は、メトリックのように、送信間隔ごとに集約されるテレメトリではない (Learn: スパンは `requests` / `dependencies` テーブルに 1 スパン 1 行で保存される)。ただし、サンプリング時は、`itemCount` で、1 行が複数件を表すことがある (例: 25% なら、残った 1 行が 4 件ぶん)。今回の行は `itemCount=1` なので、これには当たらない。
  - 「3 回の検索が、メトリックでは、1 つのデータポイントに集約されて記録されたこと」と関係があるのではないか、という見方は、上のデータからは支持されない (集約ではなく、1 回目だけが記録されている)。
  - **仮説 (有力。未確認)**: 「再起動後の最初のリクエストだけが、記録される」。サンプラーの設定 (0%) が、起動の途中で反映されるため、最初のリクエストだけが、反映前の設定 (100%) で処理された可能性がある。
    - 当てはまる点: 実験 1 でも、Function 側の記録は、再起動直後の最初のリクエスト群だけ (16:37:40、:46、:50 の 3 件)。実験 2 でも、最初の 1 回目だけ。どちらも、2 回目以降の呼び出しは、記録されていない。
    - 当てはまらない点、未確認の点: 実験 1 では、2 回目のワーカーの起動 (16:37:48 ごろ) の後の、16:37:50 のリクエストも記録されており、「設定が反映される前」だけでは、きれいに説明できない。再起動を挟まずに、時間をおいて、複数回呼び出す確認は、していない。
### 5.3 起動時の警告と、コードを変更しない理由

- 起動時の警告 (`Overriding of current MeterProvider / TracerProvider / LoggerProvider is not allowed`、`Attempting to instrument while already instrumented`) が出る。`PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY=true` により、Functions のワーカーが先にプロバイダーを設定し、コード側の `configure_azure_monitor()` の設定が、上書きできていない可能性がある。`OTEL_TRACES_SAMPLER` の環境変数は、実際に効いていた (スパンが 0 件)。
  - **コードは変更しない。** 理由:
    - ライブラリ `azure-monitor-opentelemetry` の 1.8.6 以降では、既定でログのサンプリング (`configure_azure_monitor()` の引数 `enable_trace_based_sampling_for_logs`) は `False`。`requirements.txt` は `azure-monitor-opentelemetry>=1.8.6`。確認したのは、インストール済みの 1.8.6 のソースと、PyPI の最新である 1.8.10 のソース (どちらも `_utils/configurations.py` の `_default_enable_trace_based_sampling` が `False`)。1.8.7〜1.8.9 は確認していない。
    - そのため、`configure_azure_monitor()` に渡している `enable_trace_based_sampling_for_logs=False` が、ワーカー側の設定に負けて、反映されていなくても、既定値と同じで、挙動は変わらない。
    - Python 上のトレースやその他のログも、ちゃんと記録されている (今回の実験を含め、`traces`、`exceptions`、`customMetrics` などが記録されることを確認)。実害は出ていない。
  - 警告は、ワーカー側の設定が先に行われていることを示すもので、起動のたびに出る既知の挙動として扱い、このまま残す。

## 6. 実験後の戻し方

実験用の設定を、元に戻して、再デプロイする。

| 設定                      | 戻す値                                         |
| ------------------------- | ---------------------------------------------- |
| `OTEL_TRACES_SAMPLER`     | `parentbased_trace_id_ratio`                   |
| `OTEL_TRACES_SAMPLER_ARG` | `1`                                            |
| `KNOWLEDGE_BASE_NAME`     | 本来のナレッジベース (実験 2 の時点で戻し済み) |

## 7. 使った KQL

```kusto
// サンプリングされているか (保持率が 100 未満なら、その種類はサンプリングされている)
union requests, dependencies, exceptions, traces
| where timestamp > ago(1d)
| summarize RetainedPercentage = 100/avg(itemCount), n = count() by itemType

// 実験 1: 例外ログ
exceptions
| where timestamp > datetime(<開始時刻>) and outerMessage has "Knowledge retrieval failed"
| project timestamp, type, outerMessage, operation_Id, customDimensions

// 実験 1/2: ツールのスパンと AI Search の依存関係 (0% なら 0 件)
dependencies
| where timestamp > datetime(<開始時刻>)
| where name == "foundryiq_knowledge_retrieve" or name has "knowledgebases"

// 実験 2: トークン量のメトリック
customMetrics
| where timestamp > datetime(<開始時刻>) and name startswith "kb."
| project timestamp, name, valueSum, valueCount, kb = tostring(customDimensions["kb.name"])
```

## 参考

- Reddit のスレッド: https://www.reddit.com/r/dotnet/comments/1lrm56k/azure_monitor_opentelemetry_exception_sampling/
- Application Insights でのサンプリング (OpenTelemetry): https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-sampling
- Azure Monitor OpenTelemetry の設定 (サンプリング): https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-configuration#enable-sampling
- Application Insights のメトリック (事前集計): https://learn.microsoft.com/azure/azure-monitor/app/metrics-overview#metrics-preaggregation
- Functions での OpenTelemetry: https://learn.microsoft.com/azure/azure-functions/opentelemetry-howto
