"""
Audience Q&A App — WiD 2026 Demo
FastAPI backend that proxies audience questions to the Cortex Agent
and streams Q&A pairs to the presenter view via SSE.
"""

import asyncio
import json
import os
import time
from collections import deque
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import httpx
import snowflake.connector

# ─── Config ───────────────────────────────────────────────────────────────────

SNOWFLAKE_ACCOUNT = os.environ.get("SNOWFLAKE_ACCOUNT", "SFSEEUROPE-DEMO_TNASCIMENTO_US")
SNOWFLAKE_USER = os.environ.get("SNOWFLAKE_USER", "TNASCIMENTO")
SNOWFLAKE_PASSWORD = os.environ.get("SNOWFLAKE_PASSWORD", "")
SNOWFLAKE_ROLE = os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN")
SNOWFLAKE_WAREHOUSE = os.environ.get("SNOWFLAKE_WAREHOUSE", "WID_DEMO_WH")

AGENT_DB = "RETAILBANK_2028"
AGENT_SCHEMA = "PUBLIC"
AGENT_NAME = "OPERATIONS_AGENT"

# ─── In-memory Q&A store ─────────────────────────────────────────────────────

qa_history: deque = deque(maxlen=100)
qa_event = asyncio.Event()

app = FastAPI(title="WiD 2026 — Audience Q&A")

STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


# ─── Snowflake helpers ────────────────────────────────────────────────────────

def get_snowflake_token() -> tuple[str, str]:
    """Return (session_token, account_url) using snowflake-connector-python."""
    conn = snowflake.connector.connect(
        account=SNOWFLAKE_ACCOUNT,
        user=SNOWFLAKE_USER,
        password=SNOWFLAKE_PASSWORD,
        role=SNOWFLAKE_ROLE,
        warehouse=SNOWFLAKE_WAREHOUSE,
        database=AGENT_DB,
        schema=AGENT_SCHEMA,
    )
    token = conn.rest.token
    # Build the account URL from the connection
    account_url = conn.host
    conn.close()
    return token, account_url


async def call_agent(question: str) -> str:
    """Call the Cortex Agent REST API and return the text response."""
    token, account_url = get_snowflake_token()

    agent_url = (
        f"https://{account_url}"
        f"/api/v2/databases/{AGENT_DB}/schemas/{AGENT_SCHEMA}"
        f"/agents/{AGENT_NAME}:run"
    )

    headers = {
        "Authorization": f'Snowflake Token="{token}"',
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    body = {
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": question}],
            }
        ],
        "stream": False,
    }

    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(agent_url, headers=headers, json=body)

    if resp.status_code != 200:
        return f"Error ({resp.status_code}): {resp.text[:300]}"

    data = resp.json()
    # Extract text from the agent response
    try:
        messages = data.get("messages", data.get("data", []))
        if isinstance(messages, list):
            for msg in messages:
                if msg.get("role") == "assistant":
                    content = msg.get("content", [])
                    texts = [c["text"] for c in content if c.get("type") == "text"]
                    if texts:
                        return "\n".join(texts)
        # Fallback: try direct text field
        return data.get("text", json.dumps(data, indent=2)[:1000])
    except Exception as e:
        return f"Could not parse response: {e}"


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
async def audience_page():
    """Serve the audience question form (mobile-friendly)."""
    return (STATIC_DIR / "audience.html").read_text()


@app.get("/presenter", response_class=HTMLResponse)
async def presenter_page():
    """Serve the presenter live feed view."""
    return (STATIC_DIR / "presenter.html").read_text()


@app.post("/api/ask")
async def ask_question(request: Request):
    """Accept a question from the audience, call the agent, store the result."""
    body = await request.json()
    question = body.get("question", "").strip()

    if not question:
        return JSONResponse({"error": "Empty question"}, status_code=400)

    if len(question) > 500:
        return JSONResponse({"error": "Question too long (max 500 chars)"}, status_code=400)

    # Call the agent
    try:
        answer = await call_agent(question)
    except Exception as e:
        answer = f"Sorry, I couldn't process that question right now. ({e})"

    entry = {
        "id": len(qa_history) + 1,
        "question": question,
        "answer": answer,
        "timestamp": datetime.now().strftime("%H:%M:%S"),
    }
    qa_history.append(entry)
    qa_event.set()
    qa_event.clear()

    return JSONResponse({"status": "ok", "answer": answer})


@app.get("/api/feed")
async def sse_feed():
    """Server-Sent Events feed for the presenter view."""
    async def event_generator():
        last_id = 0
        # Send existing history on connect
        for entry in qa_history:
            if entry["id"] > last_id:
                yield f"data: {json.dumps(entry)}\n\n"
                last_id = entry["id"]

        # Stream new entries
        while True:
            await asyncio.sleep(1)
            for entry in qa_history:
                if entry["id"] > last_id:
                    yield f"data: {json.dumps(entry)}\n\n"
                    last_id = entry["id"]

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/api/history")
async def get_history():
    """Return all Q&A history (for presenter page refresh)."""
    return JSONResponse(list(qa_history))


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    print("Starting Audience Q&A App...")
    print("  Audience:   http://localhost:8000/")
    print("  Presenter:  http://localhost:8000/presenter")
    uvicorn.run(app, host="0.0.0.0", port=8000)
