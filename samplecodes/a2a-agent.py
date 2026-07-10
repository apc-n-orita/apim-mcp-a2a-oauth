import asyncio
import json
import os
import sys

import httpx
from azure.identity import DefaultAzureCredential
from a2a.client import A2ACardResolver, ClientConfig, create_client
from a2a.helpers import new_text_message
from a2a.types.a2a_pb2 import Role, SendMessageRequest

_missing = [v for v in ("A2A_BASE_URL", "A2A_AGENT_CARD_PATH", "AZURE_TOKEN_SCOPE") if not os.environ.get(v)]
if _missing:
    sys.exit(f"Error: 以下の環境変数が設定されていません: {', '.join(_missing)}")

A2A_BASE_URL = os.environ["A2A_BASE_URL"]
A2A_AGENT_CARD_PATH = os.environ["A2A_AGENT_CARD_PATH"]
AZURE_TOKEN_SCOPE = os.environ["AZURE_TOKEN_SCOPE"]
CONTEXT_FILE = ".a2a_context"
DEBUG = os.environ.get("A2A_DEBUG", "0") == "1"


def load_context() -> str | None:
    try:
        with open(CONTEXT_FILE) as f:
            return json.load(f).get("context_id")
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def save_context(context_id: str) -> None:
    with open(CONTEXT_FILE, "w") as f:
        json.dump({"context_id": context_id}, f)


def extract_text(response) -> str | None:
    try:
        return "\n".join(
            part.text
            for artifact in response.task.artifacts
            for part in artifact.parts
            if part.text
        )
    except Exception:
        return None


def extract_context_id(response) -> str | None:
    if hasattr(response, "context_id") and response.context_id:
        return response.context_id
    if hasattr(response, "task") and response.task.context_id:
        return response.task.context_id
    return None


async def main():
    args = sys.argv[1:]
    if "--new" in args:
        args = [a for a in args if a != "--new"]
        os.remove(CONTEXT_FILE) if os.path.exists(CONTEXT_FILE) else None
        print("[新規会話を開始します]")

    token = DefaultAzureCredential().get_token(AZURE_TOKEN_SCOPE).token

    async def _debug_response(response: httpx.Response) -> None:
        if DEBUG:
            routed = response.headers.get("x-routed-backend", "")
            print(f"[DEBUG] HTTP {response.status_code}  X-Routed-Backend: {routed or '(none)'}")
#            await response.aread()
#            print(f"[DEBUG] response body: {response.text}")

    try:
        async with httpx.AsyncClient(
            headers={"Authorization": f"Bearer {token}"},
            timeout=120.0,
            event_hooks={"response": [_debug_response]},
        ) as http:
            agent_card = await A2ACardResolver(httpx_client=http, base_url=A2A_BASE_URL, agent_card_path=A2A_AGENT_CARD_PATH).get_agent_card()
            if DEBUG:
                print(f"[DEBUG] agent_card:\n{agent_card}")
            client = await create_client(agent=agent_card, client_config=ClientConfig(streaming=False, httpx_client=http))

            while True:
                try:
                    input_text = input("You: ").strip()
                except (EOFError, KeyboardInterrupt):
                    print("\n[終了します]")
                    break
                if not input_text or input_text.lower() in ("exit", "quit", "q"):
                    if input_text:
                        print("[終了します]")
                    break

                message = new_text_message(input_text, role=Role.ROLE_USER)
                if context_id := load_context():
                    message.context_id = context_id

                if DEBUG:
                    print(f"[DEBUG] context_id (送信): {message.context_id!r}")
                    print(f"[DEBUG] message: {message}")

                async for response in client.send_message(SendMessageRequest(message=message)):
                    if DEBUG:
                        print(response)
                    elif text := extract_text(response):
                        print(f"Agent: {text}")
                    else:
                        print(response)
                    if new_ctx := extract_context_id(response):
                        save_context(new_ctx)
    except asyncio.CancelledError:
        pass


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
