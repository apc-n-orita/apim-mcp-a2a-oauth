"""OpenTelemetry / Application Insights の初期化

function_app.py の import 時に configure() を一度だけ呼ぶ。
tracer は各モジュールから get_tracer() で取得する。

環境変数:
  APPLICATIONINSIGHTS_CONNECTION_STRING  未設定なら送信を行わず標準の logging に流れる
"""

import logging
import os

from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace

_configured = False


def configure() -> None:
    """Azure Monitor へのエクスポートを設定する (冪等)

    複数モジュールから呼ばれても二重初期化しないようフラグで守る。

    enable_trace_based_sampling_for_logs=False を明示する。
    有効にすると「サンプリングされなかったトレースに属するログレコード」が
    破棄されるため、span 内で出したエラーログが消える。
    azure-monitor-opentelemetry 1.8.6 以降は RateLimitedSampler が既定で、
    OTEL_TRACES_SAMPLER 未設定なら 5 トレース/秒に制限される
    (1.8.5 以前は sampling_ratio=1.0 の全件保持だった)。
    負荷時ほどトレースが落ちるため、エラーログをそれに従わせない。
    ディストロ既定値の False と同値だが、バージョンで変わりうるため明示する。

    トレース側のサンプリングレートを変えるときは環境変数を使う:
      OTEL_TRACES_SAMPLER=microsoft.rate_limited / OTEL_TRACES_SAMPLER_ARG=<traces/sec>
    """
    global _configured
    if _configured:
        return

    connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if connection_string:
        # ロガーのレベル抑制は configure_azure_monitor() より前に行う。
        # ロギングのレベル判定はログ出力のその瞬間に評価されるため、
        # configure_azure_monitor() の後で抑制すると、その呼び出し内部で
        # 発生するログ (例: exporter 認証のための ManagedIdentityCredential
        # 解決時の "ManagedIdentityCredential will use App Service managed
        # identity with client_id: ..." など) が抑制前に出力され、
        # Azure Monitor へのハンドラ接続もその内部で行われるため、
        # そのまま traces テーブルに送信されてしまう。
        logging.getLogger("azure.core.pipeline.policies.http_logging_policy").setLevel(
            logging.WARNING
        )
        # Functions のPythonワーカー環境ではこのロガーがINFOレベルで有効になっており、
        # 送信バッチのたびに "Transmission succeeded: Item received: N. Items accepted: N"
        # が traces テーブルに大量に残ってノイズになる (自前のログとは無関係な自己診断ログ)。
        logging.getLogger("azure.monitor.opentelemetry.exporter.export._base").setLevel(
            logging.WARNING
        )
        # azure-identity (DefaultAzureCredential配下) も同様にFunctions環境ではINFOで有効になっており、
        # retrieve() のたびに "ManagedIdentityCredential.get_token_info succeeded" 等が積み上がる。
        # azure.identity._internal.* の子ロガーはこの親のレベルを継承するため、ここ1箇所で抑制できる。
        logging.getLogger("azure.identity").setLevel(logging.WARNING)

        configure_azure_monitor(
            connection_string=connection_string,
            enable_trace_based_sampling_for_logs=False,
        )

    _configured = True


def get_tracer(name: str):
    """モジュール単位の tracer を返す"""
    return trace.get_tracer(name)
