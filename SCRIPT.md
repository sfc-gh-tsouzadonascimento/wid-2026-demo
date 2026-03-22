# Run of Show

**The Future You — A Day in the Life of a Data Professional in 2028**\
Women in Data 2026 · 60 minutes · Live demo

---

## Before Going On Stage

### Pre-requisites

- Snowsight open, logged into demo account (`SFSEEUROPE-DEMO_TNASCIMENTO_US`)
- Intelligence tab ready (ensure OPERATIONS_AGENT is active — but **without** the ComplianceSearch tool yet; it gets added live in Scene 2)
- `REPORT_PARSED` and `REPORT_CHUNKS` tables must already exist (run `sql/05_cortex_search.sql` steps 5a and 5b beforehand) — but the `COMPLIANCE_REPORTS_SEARCH` service must **not** exist yet (it gets created live in Scene 2 via the UI)
- Snowflake Notebook `PIPELINE_REVIEW` open in a separate browser tab
- FrostBank Intelligence Hub app running on port 8080 (`operational_hub_app/build.sh`)
- Terminal open with Cortex Code CLI ready
- Cortex Code UI open in Snowsight in a separate tab
- The Intelligence Hub app starts with **no question cards** — only the metrics dashboard. Questions get added live in Scene 3 via Cortex Code CLI.

### Fallback plan

- Fallback screenshots on standby (one per scene)
- If Snowflake Intelligence is slow, narrate while it processes — the audience is patient when they see real work happening

---

## Scene 1 — The Morning Briefing

**Feature:** FrostBank Intelligence Hub (dashboard) + Snowflake Intelligence + Snowflake Notebooks

**Conclusion:** AI accelerates your work, but you still need the human in the loop.

---

### Part A: The Dashboard

1. **Open the FrostBank Intelligence Hub** in the browser (localhost:8080 or the public URL).

2. **Speak to audience:**

   > "Every morning starts here. This is the FrostBank Operational Intelligence Hub — a single view of everything that happened overnight. Pipeline health, transaction activity, customer metrics, anomaly detection, fraud alerts — 17 metrics across four categories, all updated from the overnight batch."

3. **Scroll through the dashboard.** Point at the four sections: Pipeline Health (5 cards), Transaction Activity (4 cards), Customer Metrics (4 cards), Detection & Monitoring (4 cards). Gesture broadly — don't linger on any single metric.

4. **Speak to audience:**

   > "Looks good, right? Green arrows, numbers are up, pipelines ran, success rate is high. But here's the thing — when you have this many metrics on a screen, it's easy to miss something. The dashboard tells you what happened. It doesn't tell you what matters."

5. **Pause. Then:**

   > "So I don't just look at the dashboard. I ask for a briefing."

---

### Part B: The Morning Briefing via Snowflake Intelligence

6. **Switch to Snowsight. Open Snowflake Intelligence.**

7. **Type into Intelligence:**

   > Give me a morning briefing. Summarise overnight transaction activity, any anomalies detected, fraud alert outcomes, and the number of customers at risk of churn.

8. **Wait for the response.** The agent queries TRANSACTIONS, TRANSACTION_ANOMALIES, PIPELINE_RUNS, and CUSTOMERS, then writes a natural language briefing.

   Expected output (approximate): *"Overnight transaction volume was up 4.2% vs 7-day average across 5 regions. Two anomalies were flagged in EU_WEST. Fraud detection triggered 14 alerts — 11 auto-resolved, 3 escalated. However, the churn risk metric is showing ~813 customers at risk of churn — a significant increase from last quarter's ~330."*

9. **React visibly. Read the churn line aloud.**

   > "Wait — 813 customers at risk of churn? Last quarter it was around 330. That's a 150% increase. That doesn't make business sense."

10. **Speak to audience:**

    > "This is exactly why I don't just glance at the dashboard. The dashboard showed 'High-Risk Customers' as a number. The briefing gave me context — and that context is telling me something is wrong."

---

### Part C: The Catch — Investigating in the Notebook

11. **Speak to audience:**

    > "Let me investigate. We have a notebook where the churn prediction pipeline runs. Let's look at what the AI agent built overnight."

12. **Switch to the Snowflake Notebook** (`PIPELINE_REVIEW`).

13. **Run Cell 2** — the buggy churn query. Output shows **~813 at-risk customers.**

    > "There it is. 813. Let's look at the query."

14. **Scroll to the query:**

    ```sql
    SELECT COUNT(*) AS at_risk_customers   -- BUG: counts rows, not distinct customers
    FROM RETAILBANK_2028.PUBLIC.CUSTOMERS
    WHERE CHURN_RISK_SCORE > 0.6;
    ```

15. **Speak to audience:**

    > "See it? The AI used COUNT star instead of COUNT DISTINCT. Both run without error. But one customer can have multiple accounts — multiple rows in this table. So COUNT star counts every account row as a separate customer, inflating the result by roughly 2.5x."

16. **Run Cell 4** — investigation query. Shows total rows vs unique customers vs unique accounts.

    > "Look — 1,966 rows but only 800 unique customers. That's the smoking gun. One customer, multiple accounts."

17. **Run Cell 5** — the fixed query (uses COUNT DISTINCT CUSTOMER_ID). Output: **~325 at-risk customers.**

    > "325. That's in line with last quarter's trend. The AI wrote the query correctly in every other way. But it had no business context. It didn't know that one customer can have multiple accounts. That knowledge lives in your head, not in the data."

18. **Key message — speak to audience:**

    > "Technical judgement is the skill. Knowing when the answer is wrong — even before you know why. AI accelerates your work. But you are still the one who catches the mistake. The human in the loop isn't optional — it's the whole point."

---

## Scene 2 — The Compliance Task

**Feature:** Cortex Search (step-by-step creation) + Snowflake Intelligence

**Conclusion:** Doing your work faster, delivering bigger value. Talk to your data.

---

### Part A: Setting the Scene

1. **Speak to audience:**

   > "It's mid-morning now. The churn bug is fixed. But there's something else on my plate today: 30 Q1 compliance reports just landed. Basel IV, AML/KYC reviews, GDPR assessments, operational risk — the full stack. The board meets after lunch and they need a summary of the key compliance topics that require action."

2. **Pause.**

   > "Normally, that's half a day of reading. I don't have half a day. But I have Snowflake."

---

### Part B: Building Cortex Search — From Data to Service

3. **Speak to audience:**

   > "These reports are already sitting in a Snowflake stage. Our nightly pipeline parsed them with AI and chunked them into searchable segments — that's two SQL statements that run automatically. Let me show you the data."

4. **Open a Snowsight Worksheet.** Run a quick preview:

   ```sql
   SELECT COUNT(*) AS total_chunks, COUNT(DISTINCT file_name) AS total_docs
   FROM RETAILBANK_2028.PUBLIC.REPORT_CHUNKS;
   ```

   > "68 chunks across 30 documents. Each chunk is roughly 2000 characters with overlap so we don't lose context at boundaries. The hard part — reading the PDFs — is already done. Now I just need to make them searchable."

5. **Navigate in Snowsight:** Go to **AI & ML → Cortex Search** (or **Data → Databases → RETAILBANK_2028 → PUBLIC**, then click **Create → Cortex Search Service**).

6. **Walk through the UI:**

   - **Service name:** `COMPLIANCE_REPORTS_SEARCH`
   - **Source table:** `RETAILBANK_2028.PUBLIC.REPORT_CHUNKS`
   - **Search column:** `CONTENT` (the text to search over)
   - **Attributes:** `FILE_NAME` (returned with results for citation)
   - **Warehouse:** `WID_DEMO_WH`
   - **Target lag:** `1 hour`

7. **Click Create.** The service starts indexing.

   > "That's it. No embeddings pipeline, no vector database, no infrastructure to manage. I pointed it at a table, told it which column to search, and Snowflake handles the rest."

8. **Verify the service is live.** In the same UI, the service status should show as active. Alternatively, run:

   ```sql
   SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAILBANK_2028.PUBLIC;
   ```

   > "The service is live. 30 compliance reports, fully searchable."

---

### Part C: Adding Compliance Search to Snowflake Intelligence

10. **Speak to audience:**

    > "Now here's the real power move. I don't want to be the bottleneck. I want the board to be able to ask these questions themselves. Let me add this search service to our Intelligence agent."

11. **In the same worksheet, update the agent to include the ComplianceSearch tool:**

    ```sql
    CREATE OR REPLACE AGENT RETAILBANK_2028.PUBLIC.OPERATIONS_AGENT
        COMMENT = 'FrostBank Operations Agent with Compliance Search'
    FROM SPECIFICATION $$
    models:
      orchestration: auto

    instructions:
      system: |
        You are a Senior Data Professional assistant at FrostBank.
        You help with daily briefings, answer analytical questions about
        banking data, and search compliance documents.
      response: |
        Respond in a professional, concise manner suitable for
        executive consumption. When citing documents, always include
        the filename.
      orchestration: |
        For questions about transactions, customers, churn risk,
        anomalies, or pipeline runs: use BankAnalyst.
        For questions about compliance reports, regulatory findings,
        or documents: use ComplianceSearch.

    tools:
      - tool_spec:
          type: "cortex_analyst_text_to_sql"
          name: "BankAnalyst"
          description: >
            Analyses structured banking data including daily
            transactions by region, customer segments with churn risk
            scores, ML-detected anomalies, and pipeline run logs.
      - tool_spec:
          type: "cortex_search"
          name: "ComplianceSearch"
          description: >
            Searches across 30 Q1 2028 compliance and regulatory
            reports including Basel IV, AML/KYC, GDPR, and
            operational risk assessments.

    tool_resources:
      BankAnalyst:
        semantic_view: "RETAILBANK_2028.PUBLIC.BANK_ANALYTICS"
      ComplianceSearch:
        name: "RETAILBANK_2028.PUBLIC.COMPLIANCE_REPORTS_SEARCH"
        max_results: 5
        title_column: "file_name"
        id_column: "doc_chunk_id"
    $$;
    ```

    > "I've added ComplianceSearch as a tool to our existing Operations Agent. The agent now knows how to query both structured data and compliance documents."

---

### Part D: The Board Can Ask Questions Themselves

12. **Switch back to Snowflake Intelligence.**

13. **Type into Intelligence:**

    > Are there any reports flagging increased AML risk in Q1?

14. **Wait.** Intelligence searches across all 30 PDFs via Cortex Search and returns a synthesised answer with document references.

15. **Type:**

    > What are the top three compliance actions recommended across all reports?

16. **Answer appears in ~5 seconds,** with source documents listed.

17. **Speak to audience:**

    > "I haven't opened a single PDF. But I know exactly what's in all of them — and I can prove it, because the agent tells me which document it read. More importantly — the board can do this themselves now. They don't need to wait for me to prepare a summary. They can just ask."

18. **Key message:**

    > "This is what 'doing your work faster' actually looks like. Not just faster for me — faster for the whole organisation. You're not just answering questions. You're enabling everyone around you to talk to their data."

---

## Scene 3 — The Application

**Feature:** Cortex Code (UI in Snowsight) + Cortex Code (CLI) + FrostBank Intelligence Hub

**Conclusion:** Empowering the organisation.

---

### Part A: The Board Wants an App

1. **Speak to audience:**

   > "The board meeting just ended. The feedback on the compliance search was fantastic. But now the ask is: 'Can we have this as an application? Something the compliance team can use every day without going into Snowflake?'"

2. **Pause.**

   > "In the old world, that's a project. A requirements doc, a sprint, a deployment pipeline. Today — it's a prompt."

---

### Part B: Building a Streamlit App with Cortex Code UI

3. **Open Snowsight → Cortex Code interface.**

4. **Type the prompt:**

   ```
   Create a single-file Streamlit in Snowflake app. Do not create any stages, do not upload files, do not use CLI commands — just generate the Python code.

   Use get_active_session() from snowflake.snowpark.context for the session. Use the Cortex Search Python SDK to query an existing search service called COMPLIANCE_REPORTS_SEARCH in RETAILBANK_2028.PUBLIC. The search service has columns CONTENT and FILE_NAME. Use snowflake.cortex.Complete with model "mistral-large2" to synthesise a natural language answer from the search results.

   The app should:
   - Have a title "FrostBank Compliance Search"
   - Have a text input where the user types a question
   - On submit, search the service for the top 5 results, then pass the retrieved CONTENT chunks as context to Complete to generate an answer
   - Display the synthesised answer
   - Below the answer, show an expandable "Sources" section listing the FILE_NAME of each result

   Cortex Search SDK pattern:
   from snowflake.core import Root
   root = Root(session)
   svc = root.databases["RETAILBANK_2028"].schemas["PUBLIC"].cortex_search_services["COMPLIANCE_REPORTS_SEARCH"]
   results = svc.search(query=user_question, columns=["CONTENT", "FILE_NAME"], limit=5)
   # results.results is a list of dicts

   Complete pattern:
   from snowflake.cortex import Complete
   answer = Complete("mistral-large2", prompt_string)
   ```

5. **Cortex Code generates the full application code.** Scroll through it briefly — do not explain line by line.

6. **Speak to audience:**

   > "I described what I wanted in plain English. Cortex Code wrote the application."

7. **Run the generated app** directly inside Snowsight. Audience sees a compliance document Q&A interface — type a question, get an answer with source citations.

8. **Demo the app.** Type into the Streamlit app:

   > What are the key GDPR recommendations from Q1 reports?

9. **Answer appears with source document filenames.**

10. **Speak to audience:**

    > "This is now something I can hand to the compliance team. They don't need to be in Snowsight. They don't need SQL. They don't need a data background. They just ask questions and get cited answers. That's a project delivered in 2 minutes."

---

### Part C: Adding Questions to the Intelligence Hub with Cortex Code CLI

11. **Speak to audience:**

    > "But there's one more thing. We already have an Intelligence Hub — the dashboard you saw at the beginning. That's our team's one-stop shop for operational health. Let me show it again."

12. **Switch to the FrostBank Intelligence Hub** in the browser (localhost:8080).

    > "Right now this is a metrics dashboard. It shows you what happened, but you can't ask it questions. What if the team could click a question and get an AI-powered answer right here — about transactions, customers, compliance, anything? Let's build that — from the terminal."

13. **Switch to the terminal** with Cortex Code CLI.

14. **Type the prompt:**

    ```
    cortex code "In the FrostBank Intelligence Hub app (operational_hub_app), add an interactive Q&A section below the dashboard. In frontend/src/App.jsx, populate the QUESTIONS array with these 10 question objects, each with an icon and text property: 1) icon '📊' text 'What are the top-performing regions by transaction volume this month?' 2) icon '💳' text 'Break down transaction volumes across all regions for this week' 3) icon '📉' text 'Which customers are most likely to churn based on current risk scores?' 4) icon '🔍' text 'Are there any unusual patterns in recent transaction data?' 5) icon '🏦' text 'How does our customer base break down by segment and risk level?' 6) icon '📋' text 'Summarize the latest compliance findings and recommended actions' 7) icon '👤' text 'Show me the high-value customers with declining activity' 8) icon '🛡️' text 'How many fraud alerts were auto-resolved vs escalated to humans?' 9) icon '⚠️' text 'What does the AML risk landscape look like across our reports?' 10) icon '📈' text 'Give me a trend analysis of transaction values over the past week'. Also in app.py, add all 10 question texts to the ALLOWED_QUESTIONS list."
    ```

15. **Cortex Code CLI generates the diff.** Review it briefly — the audience sees the questions being added to both frontend and backend. Accept.

16. **Rebuild and restart the app:**

    ```
    cd operational_hub_app && ./build.sh
    ```

17. **Refresh the Intelligence Hub in the browser.** 10 question cards now appear below the metrics dashboard — covering transactions, customers, compliance, fraud, and trends.

18. **Click the compliance question card** ("Summarize the latest compliance findings and recommended actions"). The agent streams a response, pulling from the Cortex Search service that was created in Scene 2.

19. **Speak to audience:**

    > "From a metrics dashboard to an interactive intelligence tool — with one prompt. The team can now monitor their pipelines, spot trends, and ask questions about compliance, fraud, customer risk — all in one place. No Jira ticket. No sprint planning. No deployment pipeline. Just building."

20. **Key message:**

    > "This is what empowering the organisation looks like. You're not just the person who answers questions. You're the person who builds the tools so everyone can answer their own questions. That's the future you."

---

## Closing — The Reflection

### Spoken Narrative

> "Look at what we just did. We started with a dashboard, caught an error that the AI missed, and fixed it in a notebook. We turned 30 compliance PDFs into a searchable service with three SQL statements and gave the board direct access. We built an app and extended our operational hub — all from a terminal.
>
> Three scenes. Three conclusions.
>
> First: AI accelerates your work, but you are still the one who catches the mistake. The human in the loop isn't optional.
>
> Second: the value isn't just doing your work faster. It's enabling the people around you to talk to their data directly.
>
> Third: you're not just an analyst or an engineer. You're the person who builds the tools. You're the one who empowers the organisation.
>
> The data professional of 2028 is not smarter than you. They have the same data, the same problems. The difference is they stopped treating AI as a shortcut and started treating it as a collaborator. They stayed curious. They kept asking why the number felt wrong. They built instead of reported.
>
> The future you is already inside the work you are doing today."

---

*Run-of-show prepared March 2026 · Snowflake · Women in Data*
