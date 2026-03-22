"""
Audience Q&A App — WiD 2026 Demo
FastAPI backend that proxies audience questions to the Cortex Agent
with SSE streaming. Authenticates via snowflake-connector-python.
Works locally and in Docker/EC2.
"""

import json
import os
import sys
import threading
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

import httpx


def log(msg):
    print(f"[APP] {msg}", flush=True)


# ─── Config ───────────────────────────────────────────────────────────────────

AGENT_DB = "RETAILBANK_2028"
AGENT_SCHEMA = "PUBLIC"
AGENT_NAME = "OPERATIONS_AGENT"

ALLOWED_QUESTIONS = []

_ALLOWED_SET = {q.lower().strip() for q in ALLOWED_QUESTIONS}

FRONTEND_DIR = Path(__file__).parent / "frontend" / "dist"

app = FastAPI(title="WiD 2026 — FrostBank Operational Intelligence Hub")

# CORS for local Vite dev server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Snowflake Auth ──────────────────────────────────────────────────────────

_conn = None
_conn_lock = threading.Lock()


def _get_connection():
    global _conn
    with _conn_lock:
        if _conn is not None and not _conn.is_closed():
            return _conn

        try:
            from dotenv import load_dotenv
            load_dotenv()
        except ImportError:
            pass

        import snowflake.connector

        connect_args = {
            "account": os.environ.get("SNOWFLAKE_ACCOUNT", ""),
            "user": os.environ.get("SNOWFLAKE_USER", ""),
            "role": os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
            "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "WID_DEMO_WH"),
            "database": AGENT_DB,
            "schema": AGENT_SCHEMA,
        }

        private_key_path = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH", "")
        if private_key_path:
            from cryptography.hazmat.primitives import serialization
            key_path = Path(private_key_path).expanduser()
            log(f"Loading private key from {key_path}")
            with open(key_path, "rb") as f:
                private_key = serialization.load_pem_private_key(f.read(), password=None)
            connect_args["private_key"] = private_key.private_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        elif os.environ.get("SNOWFLAKE_PASSWORD", ""):
            connect_args["password"] = os.environ["SNOWFLAKE_PASSWORD"]
        else:
            raise RuntimeError("Set SNOWFLAKE_PRIVATE_KEY_PATH or SNOWFLAKE_PASSWORD")

        auth_method = "keypair" if private_key_path else "password"
        log(f"Connecting to Snowflake account={connect_args['account']} user={connect_args['user']} auth={auth_method}")
        _conn = snowflake.connector.connect(**connect_args)
        log(f"Connected. Host: {_conn.host}")
        return _conn


def get_token_and_host() -> tuple[str, str]:
    """Get a valid Snowflake session token and host."""
    conn = _get_connection()
    token = conn.rest.token
    host = conn.host
    if not host:
        # Construct host from account
        account = os.environ.get("SNOWFLAKE_ACCOUNT", "")
        host = f"{account}.snowflakecomputing.com"
    # Snowflake hostnames use dashes, not underscores
    host = host.lower().replace("_", "-")
    return token, host


# ─── Agent SSE proxy ─────────────────────────────────────────────────────────

async def stream_agent_response(question: str):
    """Call the Cortex Agent with streaming and yield re-mapped SSE events."""
    try:
        token, host = get_token_and_host()
        log(f"Token length: {len(token)}, Host: {host}")

        agent_url = (
            f"https://{host}"
            f"/api/v2/databases/{AGENT_DB}/schemas/{AGENT_SCHEMA}"
            f"/agents/{AGENT_NAME}:run"
        )
        log(f"Agent URL: {agent_url}")

        headers = {
            "Authorization": f'Snowflake Token="{token}"',
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        }

        body = {
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": question}]}
            ],
            "stream": True,
        }

        async with httpx.AsyncClient(timeout=httpx.Timeout(180.0, connect=30.0)) as client:
            log("Calling agent API...")
            async with client.stream("POST", agent_url, headers=headers, json=body) as resp:
                log(f"Agent response status: {resp.status_code}")

                if resp.status_code == 401:
                    # Token expired — force reconnect on next request
                    global _conn
                    with _conn_lock:
                        if _conn is not None:
                            try:
                                _conn.close()
                            except Exception:
                                pass
                            _conn = None
                    error_body = ""
                    async for chunk in resp.aiter_text():
                        error_body += chunk
                    log(f"Auth error (will reconnect): {error_body[:300]}")
                    yield f"event: error\ndata: {json.dumps({'error': 'Session expired. Please try again.'})}\n\n"
                    yield f"event: done\ndata: {{}}\n\n"
                    return

                if resp.status_code != 200:
                    error_body = ""
                    async for chunk in resp.aiter_text():
                        error_body += chunk
                    log(f"Agent error {resp.status_code}: {error_body[:500]}")
                    yield f"event: error\ndata: {json.dumps({'error': f'Agent returned {resp.status_code}: {error_body[:300]}'})}\n\n"
                    yield f"event: done\ndata: {{}}\n\n"
                    return

                current_event = None
                line_count = 0

                async for raw_line in resp.aiter_lines():
                    line = raw_line
                    line_count += 1
                    if line_count <= 5:
                        log(f"SSE line {line_count}: {line[:200]}")

                    if line.startswith("event: "):
                        current_event = line[7:].strip()
                        continue

                    if line.startswith("data: ") and current_event:
                        data_str = line[6:]
                        if data_str.strip() == "[DONE]":
                            current_event = None
                            continue
                        try:
                            data = json.loads(data_str) if data_str.strip() else {}
                        except json.JSONDecodeError:
                            log(f"JSON parse error for event {current_event}: {data_str[:200]}")
                            current_event = None
                            continue

                        if current_event == "error":
                            msg = data.get("message", str(data))
                            yield f"event: error\ndata: {json.dumps({'error': msg})}\n\n"

                        elif current_event == "response.thinking.delta":
                            text = data.get("text", "")
                            if text:
                                yield f"event: thinking\ndata: {json.dumps({'text': text})}\n\n"

                        elif current_event == "response.text.delta":
                            text = data.get("text", "")
                            if text:
                                yield f"event: text\ndata: {json.dumps({'text': text})}\n\n"

                        elif current_event == "response.status":
                            msg = data.get("message", "")
                            status = data.get("status", "")
                            if msg:
                                yield f"event: status\ndata: {json.dumps({'message': msg, 'status': status})}\n\n"

                        elif current_event == "response":
                            pass

                        current_event = None
                        continue

                    if line.strip() == "":
                        current_event = None

                log(f"Stream complete. Total lines: {line_count}")

    except Exception as e:
        log(f"ERROR in stream_agent_response: {e}")
        import traceback
        traceback.print_exc()
        yield f"event: error\ndata: {json.dumps({'error': str(e)})}\n\n"

    yield f"event: done\ndata: {{}}\n\n"


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/metrics")
async def get_metrics():
    """Return expanded operational metrics for the dashboard."""
    try:
        conn = _get_connection()
        cur = conn.cursor()

        # ── Latest date ──────────────────────────────────────────
        cur.execute(
            "SELECT MAX(TRANSACTION_DATE) FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS"
        )
        latest_date = cur.fetchone()[0]

        # ── PIPELINE HEALTH ──────────────────────────────────────
        # Pipelines run in last 24h
        cur.execute(
            "SELECT COUNT(*) FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS "
            "WHERE RUN_TIMESTAMP >= DATEADD(HOUR, -24, CURRENT_TIMESTAMP())"
        )
        pipelines_run_24h = int(cur.fetchone()[0] or 0)

        # Pipeline success rate (all time)
        cur.execute(
            "SELECT COUNT(*), "
            "SUM(CASE WHEN STATUS = 'SUCCESS' THEN 1 ELSE 0 END) "
            "FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS"
        )
        row = cur.fetchone()
        total_runs = int(row[0] or 0)
        success_runs = int(row[1] or 0)
        pipeline_success_rate = round((success_runs / total_runs) * 100, 1) if total_runs > 0 else 0

        # Total records processed (last 24h)
        cur.execute(
            "SELECT SUM(RECORDS_PROCESSED) FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS "
            "WHERE RUN_TIMESTAMP >= DATEADD(HOUR, -24, CURRENT_TIMESTAMP())"
        )
        records_processed_24h = int(cur.fetchone()[0] or 0)

        # Avg pipeline duration (seconds)
        cur.execute(
            "SELECT ROUND(AVG(DURATION_SECONDS), 0) "
            "FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS "
            "WHERE STATUS = 'SUCCESS'"
        )
        avg_pipeline_duration = int(cur.fetchone()[0] or 0)

        # AI-generated pipelines
        cur.execute(
            "SELECT COUNT(*) FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS "
            "WHERE AI_GENERATED = TRUE"
        )
        ai_generated_pipelines = int(cur.fetchone()[0] or 0)

        # ── TRANSACTION ACTIVITY ─────────────────────────────────
        # Total transactions (all time)
        cur.execute(
            "SELECT SUM(TRANSACTION_COUNT), SUM(TRANSACTION_VALUE) "
            "FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS"
        )
        row = cur.fetchone()
        total_transactions = int(row[0] or 0)
        total_value = float(row[1] or 0)

        # Today's metrics
        cur.execute(
            "SELECT SUM(TRANSACTION_COUNT), SUM(TRANSACTION_VALUE) "
            "FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS "
            "WHERE TRANSACTION_DATE = %s",
            (latest_date,),
        )
        row = cur.fetchone()
        today_transactions = int(row[0] or 0)
        today_value = float(row[1] or 0)

        # Previous day metrics (for trends)
        cur.execute(
            "SELECT SUM(TRANSACTION_COUNT), SUM(TRANSACTION_VALUE) "
            "FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS "
            "WHERE TRANSACTION_DATE = DATEADD(DAY, -1, %s)",
            (latest_date,),
        )
        row = cur.fetchone()
        prev_transactions = int(row[0] or 0)
        prev_value = float(row[1] or 0)

        # Avg transaction value (today vs prev)
        today_avg = (today_value / today_transactions) if today_transactions > 0 else 0
        prev_avg = (prev_value / prev_transactions) if prev_transactions > 0 else 0

        # Daily % change vs 7-day avg (latest date, all regions avg)
        cur.execute(
            "SELECT ROUND(AVG(PCT_CHANGE_VS_7DAY_AVG), 2) "
            "FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS "
            "WHERE TRANSACTION_DATE = %s",
            (latest_date,),
        )
        daily_pct_change = float(cur.fetchone()[0] or 0)

        # ── CUSTOMER METRICS ─────────────────────────────────────
        # Total unique customers
        cur.execute(
            "SELECT COUNT(DISTINCT CUSTOMER_ID) "
            "FROM RETAILBANK_2028.PUBLIC.CUSTOMERS"
        )
        total_customers = int(cur.fetchone()[0] or 0)

        # Active accounts
        cur.execute(
            "SELECT COUNT(DISTINCT ACCOUNT_ID) "
            "FROM RETAILBANK_2028.PUBLIC.CUSTOMERS"
        )
        active_accounts = int(cur.fetchone()[0] or 0)

        # Customers at risk of churn — BUGGY QUERY (matches the pipeline bug)
        # Counts rows instead of distinct customers → ~813 vs correct ~325
        # Because one customer has multiple accounts, each account row is
        # counted separately, inflating the number ~2.5×.
        cur.execute(
            "SELECT COUNT(*) "
            "FROM RETAILBANK_2028.PUBLIC.CUSTOMERS "
            "WHERE CHURN_RISK_SCORE > 0.6"
        )
        customers_at_risk = int(cur.fetchone()[0] or 0)

        # Avg churn risk score
        cur.execute(
            "SELECT ROUND(AVG(CHURN_RISK_SCORE), 3) "
            "FROM RETAILBANK_2028.PUBLIC.CUSTOMERS"
        )
        avg_churn_risk = float(cur.fetchone()[0] or 0)

        # ── DETECTION & MONITORING ───────────────────────────────
        # Anomalies detected
        cur.execute(
            "SELECT COUNT(*), "
            "SUM(CASE WHEN IS_ANOMALY THEN 1 ELSE 0 END) "
            "FROM RETAILBANK_2028.PUBLIC.TRANSACTION_ANOMALIES"
        )
        row = cur.fetchone()
        total_checked = int(row[0] or 0)
        anomaly_count = int(row[1] or 0)

        # Fraud alerts (from PIPELINE_RUNS fraud monitor — last run)
        cur.execute(
            "SELECT AUTO_RESOLVED_COUNT, HUMAN_ESCALATED_COUNT "
            "FROM RETAILBANK_2028.PUBLIC.PIPELINE_RUNS "
            "WHERE PIPELINE_NAME = 'FRAUD_ALERT_MONITOR' "
            "ORDER BY RUN_TIMESTAMP DESC LIMIT 1"
        )
        row = cur.fetchone()
        fraud_auto_resolved = int(row[0] or 0) if row else 0
        fraud_escalated = int(row[1] or 0) if row else 0
        fraud_alerts = fraud_auto_resolved + fraud_escalated

        cur.close()

        def trend(a, b):
            if a > b:
                return "up"
            if a < b:
                return "down"
            return "flat"

        return {
            "as_of": str(latest_date),
            # Pipeline Health
            "pipelines_run_24h": pipelines_run_24h,
            "pipeline_success_rate": pipeline_success_rate,
            "records_processed_24h": records_processed_24h,
            "avg_pipeline_duration": avg_pipeline_duration,
            "ai_generated_pipelines": ai_generated_pipelines,
            # Transaction Activity
            "total_transactions": total_transactions,
            "total_value": total_value,
            "avg_transaction_value": round(today_avg, 2),
            "daily_pct_change": daily_pct_change,
            # Customer Metrics
            "total_customers": total_customers,
            "active_accounts": active_accounts,
            "customers_at_risk": customers_at_risk,
            "avg_churn_risk": avg_churn_risk,
            # Detection & Monitoring
            "anomaly_count": anomaly_count,
            "fraud_alerts": fraud_alerts,
            "fraud_auto_resolved": fraud_auto_resolved,
            "fraud_escalated": fraud_escalated,
            # Trends
            "trends": {
                "pipelines_run_24h": "flat",
                "pipeline_success_rate": "up" if pipeline_success_rate >= 95 else "down",
                "records_processed_24h": "flat",
                "avg_pipeline_duration": "flat",
                "ai_generated_pipelines": "flat",
                "total_transactions": trend(today_transactions, prev_transactions),
                "total_value": trend(today_value, prev_value),
                "avg_transaction_value": trend(today_avg, prev_avg),
                "daily_pct_change": "up" if daily_pct_change > 0 else ("down" if daily_pct_change < 0 else "flat"),
                "total_customers": "flat",
                "active_accounts": "flat",
                "customers_at_risk": "up",
                "avg_churn_risk": "flat",
                "anomaly_count": "up" if anomaly_count > 0 else "flat",
                "fraud_alerts": "flat",
                "fraud_auto_resolved": "flat",
                "fraud_escalated": "flat",
            },
        }
    except Exception as e:
        log(f"Metrics error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)


@app.post("/api/ask")
async def ask_question(request: Request):
    """Accept a question, validate it, and stream the agent response."""
    body = await request.json()
    question = body.get("question", "").strip()

    if not question:
        return JSONResponse({"error": "Empty question"}, status_code=400)

    if question.lower().strip() not in _ALLOWED_SET:
        return JSONResponse(
            {"error": "This assistant is configured to answer the displayed questions only. Please select one from the list."},
            status_code=400,
        )

    return StreamingResponse(
        stream_agent_response(question),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ─── SPA serving ──────────────────────────────────────────────────────────────

if FRONTEND_DIR.exists():
    app.mount("/assets", StaticFiles(directory=str(FRONTEND_DIR / "assets")), name="assets")

    # Serve favicon
    favicon_path = FRONTEND_DIR / "favicon.svg"
    if favicon_path.exists():
        @app.get("/favicon.svg")
        async def favicon():
            return HTMLResponse(favicon_path.read_text(), media_type="image/svg+xml")

    @app.get("/{full_path:path}", response_class=HTMLResponse)
    async def serve_spa(full_path: str):
        """Serve the React SPA for any non-API route."""
        index = FRONTEND_DIR / "index.html"
        if index.exists():
            return index.read_text()
        return HTMLResponse("<h1>Frontend not built</h1>", status_code=500)
else:
    @app.get("/")
    async def no_frontend():
        return HTMLResponse(
            "<h1>Frontend not built</h1>"
            "<p>Run <code>cd frontend && npm run build</code> to build the React app.</p>",
            status_code=500,
        )


# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8080"))
    log(f"Starting Audience Q&A App on port {port}...")
    uvicorn.run(app, host="0.0.0.0", port=port)
