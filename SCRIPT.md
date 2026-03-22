# SCRIPT.md — Run of Show

**The Future You — A Day in the Life of a Data Professional in 2028**\
Women in Data 2026 · 60 minutes · Live demo + Slido interaction

---

## Before Going On Stage

- Snowsight open, logged into demo account, Intelligence tab ready
- Snowflake Notebook for Scene 4 open in a separate browser tab
- Terminal open with `snow` CLI authenticated (Scene 5B)
- Audience app running + ngrok URL live, QR code ready to display
- Slido session active with all 6 questions pre-loaded
- Fallback screenshots on standby (one per scene)

---

## Scene 1 — The Briefing

**Time:** 9:00 – 9:25 (25 min) \
**Feature:** Snowflake Intelligence (agentic briefing)

### Flow

1. **Open Snowflake Intelligence** in Snowsight.

2. **Type into Intelligence:**

   > Give me a morning briefing. Summarise overnight transaction activity, any anomalies detected, fraud alert outcomes, and pipeline run status.

3. **Wait for the response.** The agent queries TRANSACTIONS, TRANSACTION_ANOMALIES, and PIPELINE_RUNS, then writes a natural language briefing.

   Expected output (approximate): *"Overnight transaction volume was up 4.2% vs 7-day average. Two anomalies flagged in the EU_WEST region. Card fraud detection model triggered 14 alerts — 11 resolved automatically. One pipeline failed at 03:17 and restarted successfully."*

4. **Speak to audience:**

   > "I didn't write a prompt. I didn't write SQL. The Intelligence agent queried the TRANSACTIONS table, reasoned over it, and wrote this itself. Every morning."

5. **Pause. Then:**

   > "But... let me show you something."

6. **Read the fraud alert line aloud.** Then type into Intelligence:

   > Show me the raw fraud alert counts from last night's pipeline runs.

7. **The agent returns the table.** The data shows: `AUTO_RESOLVED_COUNT = 11`, `HUMAN_ESCALATED_COUNT = 3` — the briefing said it the other way around (or described it ambiguously).

8. **Speak to audience:**

   > "The agent summarised it backwards. The skill is not reading the output. It is reading it critically — and knowing what question to ask next."

### Slido Moment

**Display QR code.** Question:

> *"What would you want your AI morning briefing to tell you every day?"*

Run for 90 seconds. Pick the best answer from the live word cloud.

**Live generation:** Take the winning answer and type into a Snowsight Worksheet:

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
  'Write a one-paragraph AI morning briefing for someone whose job involves: [WINNING ANSWER]. Make it specific, concise, and actionable.'
) AS briefing;
```

Read the generated briefing aloud. This is the moment that makes the audience feel it personally.

---

## Scene 2 — The Unexpected Question

**Time:** 9:25 – 9:50 (20 min) \
**Feature:** Snowflake Intelligence + Cortex Analyst (natural language → SQL → chart)

### Flow

1. **Show the "Slack message"** (mocked screenshot or on-screen chat bubble):

   > *"Hey — before the board call, can you tell me which of our high-volume customers are most at risk of leaving this quarter?"*

2. **Speak to audience:**

   > "No prior analysis exists. No dashboard. No Jira ticket. Just a question that needs an answer before 11am."

3. **Type into Intelligence** (same chat, continuing from Scene 1):

   > Which customer segments have the highest churn risk among accounts with transaction volume in the top 50 this month?

4. **Wait.** Intelligence reasons visibly: identifies relevant tables, generates a join, runs it, renders a bar chart. The audience watches every step.

5. **Do not touch any SQL, any chart config, any filter.** Let Intelligence do all of it.

6. **Chart renders:** churn risk score by segment, top 50 accounts highlighted.

7. **Speak to audience:**

   > "Three years ago this took half a day, a Jira ticket, and three Slack threads. Today it took 8 seconds inside the same interface I was already in. The question I need to be ready for is not the one I already have a dashboard for."

### Slido Moment

**Display QR code.** Question:

> *"What's a question your exec asks that you can never answer fast enough?"*

Collect 3–4 answers. **Pick one from the audience. Run it live** against the dataset in Intelligence. If the question doesn't map perfectly to the schema, use a close approximation — the audience doesn't know the exact schema.

**This is the highest-impact interactive moment in the session.**

---

## Scene 3 — The Document Pile

**Time:** 9:50 – 10:10 (20 min) \
**Feature:** Snowflake Intelligence (document agent) + Cortex Search

### Flow

1. **Set the scene:**

   > "It's lunchtime. An email lands: 30 Q1 compliance reports just dropped. The board needs a summary by 3pm. Let's see what we can do."

2. **Still inside Intelligence.** Type:

   > Are there any reports flagging increased AML risk in Q1?

3. **Wait.** Intelligence searches across all 30 PDFs via Cortex Search and returns a synthesised answer with document references and page citations.

4. **Type:**

   > What are the top three compliance actions recommended across all reports?

5. **Answer appears in ~5 seconds,** with source documents listed.

6. **Speak to audience:**

   > "I haven't opened a single PDF. But I know exactly what's in all of them — and I can prove it, because the agent tells me which document it read."

7. **Optional — audience Q&A app:** If the audience app is running, mention that the audience can also ask the agent questions directly from their phones (show the QR code briefly). Pick 1–2 audience questions from the presenter feed and run them.

### Slido Moment

**Display QR code.** Question:

> *"Ask the documents anything."*

Audience submits questions live. **Pick 2–3 and run them in Intelligence.** Keep it tight — 90 seconds of questions, 2 live answers, move on.

**This is the crowd-pleaser scene. It feels like magic.**

---

## Scene 4 — The Catch

**Time:** 10:10 – 10:25 (15 min) \
**Feature:** Snowflake Notebooks + Cortex Complete (code review)

### Flow

1. **Set the scene:**

   > "It's 2pm. An AI agent built a churn prediction refresh pipeline overnight. It's scheduled to run before the board call. Let's review it."

2. **Open the Snowflake Notebook** (pre-created from `sql/08_notebook_scene4.sql`).

3. **Run Cell 2** — loads pipeline metadata. Normal output.

4. **Run Cell 3** — the buggy churn query. Output shows **~1,847 at-risk customers.**

5. **Pause. React visibly:**

   > "That's a 200% increase in one month. That doesn't make business sense."

6. **Run Cell 4** — investigation query. Shows the JOIN clause:

   ```sql
   ON c.CUSTOMER_ID = a.ACCOUNT_ID   -- BUG
   ```

   Explain: both columns are integers, so no type error — but one customer can have multiple accounts, so the join inflates results by ~3x.

7. **Run Cell 5** — the fixed query (queries CUSTOMERS directly). Output: **~589 at-risk customers.** In line with trend.

8. **Run Cell 6** — side-by-side comparison.

9. **Speak to audience:**

   > "The AI wrote 90% of this pipeline correctly. But it had no business context. It didn't know that one customer can have multiple accounts. That knowledge lives in your head, not in the data."

10. **Key message:**

    > "Technical judgment is the skill. Knowing when the answer is wrong even before you know why."

### Slido Moment

**Display QR code.** Question:

> *"Have you ever caught an AI (or a colleague!) making this kind of mistake?" — Yes / No / Tell us what happened*

Quick poll. The "Tell us what happened" answers will be gold — **read 1–2 aloud.** Creates connection and validates the audience's real experience.

---

## Scene 5 — The Build

**Time:** 10:25 – 10:45 (20 min) \
**Feature:** Cortex Code (UI in Snowsight) + Cortex Code (CLI)

### Part A: Cortex Code UI

1. **Set the scene:**

   > "It's 4pm. Instead of sending the board a report about those compliance documents, I'm going to ship them a tool."

2. **Open Snowsight → Cortex Code interface.**

3. **Type the prompt:**

   > Write a Streamlit in Snowflake application that connects to the COMPLIANCE_REPORTS_SEARCH Cortex Search service in RETAILBANK_2028.PUBLIC and lets a user ask questions about compliance reports. Include a results panel that shows the source document filename and page number for each answer. Use SNOWFLAKE.CORTEX.COMPLETE to synthesise answers from the search results. Add a clean, professional UI with a sidebar for settings.

4. **Cortex Code generates the full application code.** Scroll through it briefly — do not explain line by line.

5. **Speak to audience:**

   > "I described what I wanted in plain English. Cortex Code wrote the application. Let me show you it running."

6. **Run the generated app** directly inside Snowsight. Audience sees the same document Q&A interface from Scene 3, now as a deployable tool.

7. **Speak to audience:**

   > "This is now something I can hand to the Compliance team. They don't need to be in Snowsight. They don't need a data background. It just works."

### Part B: Cortex Code CLI

8. **Switch to terminal.** (Have it pre-opened.)

   > "For those of you who live in the terminal — same capability, same model, different interface."

9. **Run in terminal:**

   ```
   cortex code "Add a date filter sidebar widget to the compliance report Q&A app so users can narrow results by quarter (Q1, Q2, Q3, Q4 2028)"
   ```

10. **CLI returns the code diff.** Paste it in, rerun the app.

11. **Speak to audience:**

    > "Whether you're in a browser or a terminal, you're working with the same intelligence. The interface is your choice. The outcome is the same."

### Slido Moment

**Display QR code.** Question:

> *"What should the app do next?" — A) Filter by report type · B) Export key findings · C) Add a risk score summary panel*

Audience votes. **Prompt Cortex Code to add the winning feature — live in the UI.**

Pre-tested prompts for each option (see `docs/scene5_prompts.md`):
- **A:** "Add a multiselect filter in the sidebar that lets users filter by report type: Basel IV, AML/KYC, GDPR, Operational Risk"
- **B:** "Add an 'Export Findings' button that generates a downloadable summary of the top 5 findings from the current search results as a text file"
- **C:** "Add a risk score summary panel at the top of the page that shows the average risk level mentioned across all search results, displayed as a metric card with a color indicator"

The voted feature is pre-prepared and tested. This is theater with a real outcome: the feature actually gets added and works.

---

## Scene 6 — The Reflection

**Time:** 10:45 – 11:00 (15 min) 

### Spoken Narrative

> "Look at what we just did in 60 minutes. We handled a morning briefing and caught an AI error. We answered an exec's question in real-time. We processed 30 documents without opening one. We found a pipeline bug before it hit the board. We shipped a tool.
>
> None of that required writing SQL from scratch. None of it required a Jira ticket. None of it required waiting.
>
> Here's the uncomfortable truth: the data professional who does all of this in 2028 is not smarter than you. They are not more technical. They have the same data, the same problems. The difference is they stopped treating AI as a shortcut and started treating it as a collaborator. They stayed curious. They kept asking why the number felt wrong. They built instead of reported.
>
> Your current job is your laboratory. Every project you touch this week is a chance to try one thing differently. Use natural language instead of writing the query yourself. Let the model draft the summary and then edit it. Build the tool instead of sending the spreadsheet.
>
> The future you is already inside the work you are doing today."

### Final Slido Moment

**Display QR code.** Question:

> *"What's the first thing you'll try on Monday?"*

Leave on screen while people leave. **Read a few answers aloud.** End on a real answer from a real person in the room.

---



*Run-of-show prepared March 2026 · Snowflake · Women in Data*
