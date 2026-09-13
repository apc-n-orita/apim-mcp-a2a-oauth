import os
from azure.ai.textanalytics import TextAnalyticsClient
from azure.identity import DefaultAzureCredential
from azure.ai.textanalytics import PiiEntityCategory

# 環境変数から認証情報を取得
endpoint = os.environ["LANGUAGE_ENDPOINT"]
# クライアントの初期化
client = TextAnalyticsClient(
    endpoint=endpoint,
    credential=DefaultAzureCredential()
)

# PII検出の実行
documents = [
    "田中太郎の電話番号は080-1111-2222です。連絡先は tanaka@example.com です。"
]

response = client.recognize_pii_entities(
    documents,
    language="ja"
)

# 結果の処理
for doc in response:
    if not doc.is_error:
        print(f"元のテキスト: {documents[0]}")
        print(f"マスク後のテキスト: {doc.redacted_text}")
        print("\n検出されたPIIエンティティ:")
        for entity in doc.entities:
            print(f"  - テキスト: {entity.text}")
            print(f"    カテゴリ: {entity.category}")
            print(f"    信頼度スコア: {entity.confidence_score}")
            print(f"    位置: {entity.offset} (長さ: {entity.length})")
    else:
        print(f"エラー: {doc.error.message}")
