---
name: fix-sentry-issues
description: Use Sentry MCP to discover, triage, and fix production issues with root-cause analysis. Use when asked to fix Sentry issues, triage production errors, investigate error spikes, or clean up Sentry noise. Requires Sentry MCP server. Triggers on "fix sentry", "triage errors", "production bugs", "sentry issues".
---

# Fix Sentry Issues

Systematically discover, triage, investigate, and fix production issues using Sentry MCP. One PR per issue, root-cause analysis required.

## Critical Rule: Truth-Seek, Don't Suppress

**NEVER** treat log level changes as fixes. Changing `logger.error` to `logger.warn` silences Sentry but doesn't fix the user's experience.

A log level change is valid ONLY after:
1. You've investigated the root cause
2. Confirmed the user isn't affected (fallback path exists)
3. The behavior is genuinely expected (external API 404, etc.)

Ask: **"Why does this fail?"** not **"How do I make Sentry quiet?"**

## Phase 1: Discover

Use Sentry MCP to find the org, project, and all unresolved issues. Use `ToolSearch` first to load the Sentry MCP tools.

```
mcp__sentry__find_organizations()
mcp__sentry__find_projects(organizationSlug, regionUrl)
mcp__sentry__search_issues(
  organizationSlug, projectSlugOrId, regionUrl,
  naturalLanguageQuery: "all unresolved issues sorted by events",
  limit: 25
)
```

Build a triage table before starting any work:

```markdown
| ID | Title | Events | Action | Reason |
|----|-------|--------|--------|--------|
| PROJ-A | Error in save | 14 | Fix | User-facing save failure |
| PROJ-B | GM_register... | 3 | Ignore | Greasemonkey extension |
```

## Phase 2: Triage

Classify every issue before writing any code.

### Fix (our code, user-facing impact)
- Multiple events establishing a pattern
- User sees degraded experience (error status, missing data, broken UI)
- Recurring on every run/sync (stale references, cron-triggered)
- Architectural issues (timeout budgets, missing fallbacks)

### Ignore (third-party noise)
- Browser extension code (`GM_registerMenuCommand`, `CONFIG`, `currentInset`, MetaMask JSON-RPC)
- Stale module imports after deploy (`ChunkLoadError` — self-resolving)
- Single-event transients with no reproduction path

### Resolve (already fixed)
- Issue was addressed by a recent commit or PR
- External fix (dependency update, infrastructure change)

Apply triage decisions:
```
mcp__sentry__update_issue(issueId, organizationSlug, regionUrl, status: "ignored")  // noise
mcp__sentry__update_issue(issueId, organizationSlug, regionUrl, status: "resolved") // already fixed
```

## Phase 3: Investigate

For each "Fix" issue, work through these steps **in order**.

### 3a. Pull event-level data

Issue summaries hide the details you need. Always pull actual events:

```
mcp__sentry__search_issue_events(
  issueId, organizationSlug, regionUrl,
  naturalLanguageQuery: "all events with extra data",
  limit: 15
)
```

Extract: actual URLs, request parameters, stack traces, timestamps, user context. These are the real inputs that triggered the failure.

### 3b. Read the failing code path

Follow the stack trace. Read every file in the chain. Understand what the code does before proposing changes. Use subagents for parallel file exploration if the stack is deep.

### 3c. Reproduce locally

Use the actual failing inputs from Sentry events:
- Call the function with the exact data that failed
- `fetch()` the actual URLs that timed out — are they reachable?
- Check if the failure is in our code or an external service
- If external: does our code have a fallback? Should it?

### 3d. Identify root cause

Common root causes (from real production experience):

| Pattern | Root Cause | Real Fix |
|---------|-----------|----------|
| DB rejects "invalid json" | Unsanitized input (null bytes, control chars, lone surrogates) | Sanitize before insert |
| External API timeout/403 | No fallback when scraper fails | Add lightweight fallback (cheerio, direct fetch) |
| Processing stuck in "error" | Timeout budget doesn't account for full pipeline | Adjust timeouts, save minimal metadata on timeout |
| Zod error in Sentry but caught in code | `.parse()` throws before try-catch, Sentry middleware captures it | Use `.safeParse()` |
| Same error on every cron run | Stale reference to deleted external resource | Detect staleness, auto-clean |
| Expected API 404 flooding Sentry | `logger.warn` sends to Sentry for expected outcomes | Downgrade to `logger.info` (valid here — fallback exists) |

### 3e. Know your log levels

Log levels control what reaches Sentry:

| Level | Sends to Sentry? | Use for |
|-------|-------------------|---------|
| `logger.error` | Yes (error) | Unexpected bugs, states that should never occur |
| `logger.warn` | Yes (warning) | Handled failures worth monitoring |
| `logger.info` | No | Expected operational outcomes with working fallback paths |

## Phase 4: Fix

### 4a. Branch from main
```bash
git checkout main && git pull
git checkout -b fix/<descriptive-name>
```

One branch per issue. Keep fixes focused.

### 4b. Write tests first

Tests must use data derived from actual Sentry events, not hypothetical inputs. The test should fail before the fix and pass after.

### 4c. Implement the fix

Fix the root cause, not the symptom. If the fix is just a log level change, step back — you haven't found the root cause yet (unless it's the "expected outcome" pattern from the table above).

### 4d. Verify

- Run tests (e.g., `bun run test`)
- Run lint
- Confirm the fix handles the actual failing inputs from Sentry events

### 4e. Create PR

```bash
git push -u origin fix/<descriptive-name>
gh pr create --title "<short title>" --body "$(cat <<'EOF'
## Summary
- **Root cause**: [What was actually wrong]
- **Fix**: [What changed and why]

## Test plan
- [x] Tests written using data from Sentry events
- [x] All tests pass
- [x] Lint passes
EOF
)"
```

### 4f. Resolve in Sentry

After PR is merged:
```bash
git checkout main && git pull
```
```
mcp__sentry__update_issue(issueId, organizationSlug, regionUrl, status: "resolved")
```

## Phase 5: Repeat

Work through issues by priority (most events first). After each PR:
1. Return to main, pull latest
2. Pick next issue from the triage table
3. Start Phase 3 again

### Combining related issues

If two issues share the same root cause or keep conflicting on the same files, combine into a single PR. Signs:
- Same file modified by both fixes
- One fix is incomplete without the other
- They solve different facets of the same user problem

## Checklist Per Issue

```
[ ] Pulled event-level data (not just issue summary)
[ ] Read the failing code path
[ ] Tested with actual failing inputs locally
[ ] Identified root cause (not just symptom)
[ ] Tests use real-world data from Sentry events
[ ] Tests pass, lint passes
[ ] PR created with root cause explanation
[ ] Sentry issue resolved after merge
```
