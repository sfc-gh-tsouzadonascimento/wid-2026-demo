# The Future You — A Day in the Life of a Data Professional in 2028

**Women in Data 2026 · Live Demo Session**\
*Teresa Nascimento + Galiya Warrier · Snowflake*

A 60-minute live demo session following a fictional senior data professional through a day at RetailBank 2028. Every scene is a live Snowflake demo showcasing a different AI capability — from agentic briefings to building and shipping an app on stage.

---

## Architecture

All demos run on a single synthetic dataset: **RETAILBANK_2028**. One database, one story, no context-switching.

```
RETAILBANK_2028
├── TRANSACTIONS        — 90 days × 5 regions, 3 anomaly spikes seeded
├── CUSTOMERS           — ~2,000 rows, 1:many customer→account relationship
├── PIPELINE_RUNS       — 30 pipeline run logs (1 with seeded error)
├── TRANSACTION_ANOMALIES — ML model output (anomaly scores + flags)
├── REPORT_CHUNKS       — chunked text from 30 compliance PDFs
├── BANK_ANALYTICS      — semantic view (4 tables, dimensions, measures)
├── COMPLIANCE_REPORTS_SEARCH — Cortex Search service over PDFs
├── OPERATIONS_AGENT    — Cortex Agent (analyst + search tools)
└── @REPORTS_STAGE      — 30 synthetic PDF compliance reports
```

### Snowflake Features Used

| Feature | Scene |
|---|---|
| Snowflake Intelligence (Cortex Agent) | 1, 2, 3 |
| Cortex Analyst + Semantic Views | 2 |
| Cortex Search | 3 |
| Snowflake ML ANOMALY_DETECTION | 1 (data prep) |
| Cortex Complete | PDF generation, Scene 1 Slido |
| AI_PARSE_DOCUMENT | PDF parsing pipeline |
| Snowflake Notebooks | 4 |
| Cortex Code (UI + CLI) | 5 |

---

## Session Scenes

| Time | Scene | What Happens |
|---|---|---|
| 9:00–9:25 | **1. The Briefing** | Agent auto-summarises overnight data. Presenter catches an AI error. |
| 9:25–9:50 | **2. The Unexpected Question** | CFO asks an ad-hoc question. Natural language → SQL → chart in seconds. |
| 9:50–10:10 | **3. The Document Pile** | 30 compliance PDFs arrive. Agent answers questions without opening one. |
| 10:10–10:25 | **4. The Catch** | AI-generated pipeline has a wrong join key. Presenter finds the bug. |
| 10:25–10:45 | **5. The Build** | Build and deploy a compliance Q&A app live — UI then CLI. |
| 10:45–11:00 | **6. The Reflection** | No demo. Spoken narrative + final Slido. |

---

## Repository Structure

```
wid-2026-demo/
├── sql/
│   ├── 01_setup.sql              # Database, warehouse, stage, cross-region
│   ├── 02_data_seed.sql          # Transactions, customers, pipeline_runs
│   ├── 03_anomaly_detection.sql  # ML model train + detect → anomalies table
│   ├── 05_cortex_search.sql      # Parse PDFs, chunk, create search service
│   ├── 06_semantic_view.sql      # Semantic view YAML (4 tables)
│   ├── 07_create_agent.sql       # OPERATIONS_AGENT (analyst + search tools)
│   └── 08_notebook_scene4.sql    # Notebook cells for Scene 4 (buggy pipeline)
├── scripts/
│   ├── 04_generate_pdfs.py       # Generate 30 synthetic compliance PDFs
│   └── requirements.txt          # fpdf2, snowflake-connector-python
├── audience_app/
│   ├── app.py                    # FastAPI backend (Cortex Agent REST API)
│   ├── requirements.txt          # fastapi, uvicorn, httpx, etc.
│   ├── .env.example              # Snowflake connection template
│   └── static/
│       ├── audience.html         # Mobile-first question submission form
│       └── presenter.html        # Full-screen live Q&A feed (SSE)
├── docs/
│   └── scene5_prompts.md         # Pre-tested Cortex Code prompts for Scene 5
├── assets/
│   └── WiD_Session_Blueprint.pdf # Original session blueprint
├── SCRIPT.md                     # Run-of-show for the live demo
└── README.md                     # This file
```

---

## Setup

### Prerequisites

- Snowflake account with ACCOUNTADMIN access
- Python 3.10+ (for PDF generation)
- Snowflake CLI (`snow`) v3+ with Cortex Code (for deployment and Scene 5)

### Option A: Deploy with Cortex Code (recommended)

Open Cortex Code (CLI or UI) pointed at your demo account and paste the following prompt:

```
Deploy the WiD 2026 "The Future You" demo to Snowflake. Read and execute
every SQL and Python file in this repo in numbered order. Here is what each
step does — execute them sequentially, waiting for each to finish before
starting the next:

1. Read sql/01_setup.sql and execute every statement — creates the
   RETAILBANK_2028 database, WID_DEMO_WH warehouse, REPORTS_STAGE (with
   DIRECTORY enabled), and enables cross-region inference.

2. Read sql/02_data_seed.sql and execute every statement — seeds
   TRANSACTIONS (~450 rows), CUSTOMERS (~2,000 rows), and PIPELINE_RUNS
   (30 rows) with demo data including seeded errors for Scene 1.

3. Read sql/03_anomaly_detection.sql and execute every statement — creates
   training/detection views, trains an ANOMALY_DETECTION model on 80 days
   of clean data, runs detection on the last 10 days, and persists results
   to TRANSACTION_ANOMALIES. Use a longer timeout (up to 5 min) for the
   model training step.

4. Install Python dependencies from scripts/requirements.txt
   (fpdf2, snowflake-connector-python), then run scripts/04_generate_pdfs.py
   to generate 30 synthetic compliance PDFs and upload them to
   @RETAILBANK_2028.PUBLIC.REPORTS_STAGE. This calls Cortex Complete for
   content generation so it may take a few minutes.

5. Read sql/05_cortex_search.sql and execute every statement — parses the
   uploaded PDFs with AI_PARSE_DOCUMENT, chunks text into ~2000-char segments,
   and creates the COMPLIANCE_REPORTS_SEARCH Cortex Search service. The
   parse step may take a few minutes for 30 PDFs.

6. Read sql/06_semantic_view.sql and execute every statement — creates the
   BANK_ANALYTICS semantic view covering transactions, customers, anomalies,
   and pipeline runs.

7. Read sql/07_create_agent.sql and execute every statement — creates the
   OPERATIONS_AGENT Cortex Agent with BankAnalyst (text-to-SQL) and
   ComplianceSearch (document search) tools.

8. Read sql/08_notebook_scene4.sql and create a Snowflake Notebook called
   "Pipeline Review — The Catch" in the RETAILBANK_2028 database. The file
   documents 6 cells (markdown and SQL). Create the notebook with these cells:
   - Cell 1: Markdown title and description
   - Cell 2: SQL — the buggy churn query (JOIN on wrong key)
   - Cell 3: Markdown — result observation (1,847 vs 612)
   - Cell 4: SQL — investigation query
   - Cell 5: SQL — the fixed query
   - Cell 6: Markdown — explanation and lesson

After all steps complete, verify by running:
  SHOW AGENTS IN SCHEMA RETAILBANK_2028.PUBLIC;
  SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAILBANK_2028.PUBLIC;
  SHOW SEMANTIC VIEWS IN SCHEMA RETAILBANK_2028.PUBLIC;
  SELECT COUNT(*) FROM RETAILBANK_2028.PUBLIC.TRANSACTIONS;
  SELECT COUNT(*) FROM RETAILBANK_2028.PUBLIC.CUSTOMERS;
  SELECT COUNT(*) FROM RETAILBANK_2028.PUBLIC.REPORT_CHUNKS;

Report a summary of what was created and any errors.
```

Cortex Code will read each file, execute the SQL statements, run the Python script, create the notebook, and verify the deployment.

### Option B: Manual step-by-step

Run the numbered SQL scripts in order in Snowsight Worksheets (or any SQL client connected to your demo account).

#### Step 1: Database and infrastructure

Run `sql/01_setup.sql`. Creates the database, warehouse, stage, and enables cross-region inference.

#### Step 2: Seed data

Run `sql/02_data_seed.sql`. Creates and populates TRANSACTIONS (~450 rows), CUSTOMERS (~2,000 rows), and PIPELINE_RUNS (30 rows).

**Seeded errors:**
- PIPELINE_RUNS row 1: `AUTO_RESOLVED_COUNT=11, HUMAN_ESCALATED_COUNT=3` — the agent tends to swap these in its summary (Scene 1 error).
- TRANSACTIONS: 3 anomaly spikes in EU_WEST at days -3, -6, -8.

#### Step 3: Anomaly detection model

Run `sql/03_anomaly_detection.sql`. Trains `SNOWFLAKE.ML.ANOMALY_DETECTION` on 80 days of clean data, runs detection on the last 10 days, and persists results to TRANSACTION_ANOMALIES.

#### Step 4: Generate compliance PDFs

```bash
cd scripts
pip install -r requirements.txt
python 04_generate_pdfs.py
```

Generates 30 synthetic compliance PDFs (Basel IV, AML/KYC, GDPR, Operational Risk) using Cortex Complete, renders them with fpdf2, and uploads to `@REPORTS_STAGE`.

Requires a Snowflake connection (uses the default `snow` CLI connection or environment variables).

#### Step 5: Cortex Search service

Run `sql/05_cortex_search.sql`. Parses PDFs with `AI_PARSE_DOCUMENT`, chunks text into ~2,000-char segments with 200-char overlap, and creates the `COMPLIANCE_REPORTS_SEARCH` Cortex Search service.

#### Step 6: Semantic view

Run `sql/06_semantic_view.sql`. Creates the `BANK_ANALYTICS` semantic view covering TRANSACTIONS, CUSTOMERS, TRANSACTION_ANOMALIES, and PIPELINE_RUNS with dimensions, measures, relationships, and verified queries.

#### Step 7: Create the agent

Run `sql/07_create_agent.sql`. Creates `OPERATIONS_AGENT` with two tools:
- **BankAnalyst** — Cortex Analyst text-to-SQL over the semantic view
- **ComplianceSearch** — Cortex Search over the compliance PDFs

#### Step 8: Notebook (Scene 4)

`sql/08_notebook_scene4.sql` documents the 6 notebook cells. Create a Snowflake Notebook manually in Snowsight and paste the cells from this file:
1. Title cell (markdown)
2. Buggy churn query (JOIN on wrong key — `CUSTOMER_ID = ACCOUNT_ID`)
3. Result observation (markdown)
4. Investigation query
5. Fixed query (direct CUSTOMERS query)
6. Explanation and lesson (markdown)

---

## Audience Q&A App

A lightweight FastAPI web app that lets audience members ask questions to the OPERATIONS_AGENT during Scene 3 (or any time).

### Setup and run via Cortex Code

```
Set up and start the audience Q&A app from the audience_app/ directory.
Install the Python dependencies from audience_app/requirements.txt, then
copy audience_app/.env.example to audience_app/.env and ask me for the
Snowflake credentials to fill in. Once the .env is configured, start the
FastAPI server with: uvicorn app:app --host 0.0.0.0 --port 8000
from the audience_app directory.
```

### Manual setup

```bash
cd audience_app
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your Snowflake credentials
```

### Run locally

```bash
cd audience_app
uvicorn app:app --host 0.0.0.0 --port 8000
```

- **Audience view:** `http://localhost:8000/` — mobile-first form for submitting questions
- **Presenter view:** `http://localhost:8000/presenter` — full-screen live Q&A feed (SSE)

### Public hosting for the conference

**Recommended: ngrok** (simplest for a conference setting)

```bash
ngrok http 8000
```

Share the ngrok URL with the audience via QR code. No deployment needed.

**Alternatives:** Render, Railway, or any platform that supports Python/FastAPI.

---

## Teardown

To remove all demo objects from the account, run in Cortex Code or a Worksheet:

```sql
DROP DATABASE IF EXISTS RETAILBANK_2028;
DROP WAREHOUSE IF EXISTS WID_DEMO_WH;
```

---

*Session blueprint prepared March 2026 · Teresa Nascimento + Galiya Warrier · Snowflake · Women in Data*
