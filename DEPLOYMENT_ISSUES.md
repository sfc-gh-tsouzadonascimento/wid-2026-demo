# Deployment Issues & Fixes

Issues encountered deploying the WiD 2026 demo. Reference this to avoid repeating mistakes.

## 1. Semantic View: verified_queries requires `name` field

**Error:** `Required field 'name' in VerifiedQuery is missing`

**Cause:** Each entry under `verified_queries` must have a `name` field. Snowflake Intelligence / Cortex Analyst rejects the YAML without it.

**Fix:** Add a unique `name` to every verified query entry:
```yaml
verified_queries:
  - name: churn_risk_by_segment   # REQUIRED
    question: "..."
    sql: >
      SELECT ...
```

## 2. Semantic View: CREATE syntax

**Error:** `syntax error line 2 at position 0 unexpected 'AS'`

**Cause:** `CREATE SEMANTIC VIEW ... AS YAML $$ ... $$` is not valid SQL.

**Fix:** Use the system function instead:
```sql
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('DB.SCHEMA', $$ yaml_content $$, FALSE);
```

## 3. Semantic View: relationship requires primary/unique key

**Error:** `The referenced key in the relationship must be the primary or unique key`

**Cause:** Joining `customers.region = transactions.txn_region` fails because `region` is not a unique key.

**Fix:** Remove relationships between tables that don't share a proper PK/FK. Each table can still be queried independently by the agent.

## 4. Cortex Agent: `sample_questions` not supported

**Error:** `agent spec is invalid: unrecognized field sample_questions`

**Cause:** The `sample_questions` field is not part of the CREATE AGENT YAML spec.

**Fix:** Remove the `sample_questions` block from the agent specification.

## 5. fpdf2: Unicode characters in core fonts

**Error:** `FPDFUnicodeEncodingException: Character "\u2014" ... outside the range of characters supported`

**Cause:** Helvetica (a core PDF font) only supports latin-1. Em-dashes, smart quotes, and other Unicode from Cortex Complete output break rendering.

**Fix:** Sanitize all text before passing to fpdf2:
```python
def sanitize_text(text):
    replacements = {"\u2014": "-", "\u2013": "-", "\u2018": "'", "\u2019": "'", "\u201C": '"', "\u201D": '"', ...}
    for orig, repl in replacements.items():
        text = text.replace(orig, repl)
    return text.encode("ascii", errors="replace").decode("ascii")
```

## 6. AI_PARSE_DOCUMENT: stage encryption

**Error:** `Input files from stages with Client Side Encryption is not supported`

**Cause:** Default internal stages use `SNOWFLAKE_FULL` encryption, which AI_PARSE_DOCUMENT does not support.

**Fix:** Create the stage with SSE encryption:
```sql
CREATE STAGE my_stage DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
```

## 7. AI_PARSE_DOCUMENT: function signature

**Error:** `invalid argument for function [AI_PARSE_DOCUMENT]`

**Cause:** Old syntax `AI_PARSE_DOCUMENT(@stage, path, options)` is no longer valid.

**Fix:** Use `TO_FILE()`:
```sql
AI_PARSE_DOCUMENT(TO_FILE('@stage', relative_path), {'mode': 'LAYOUT'})
```
