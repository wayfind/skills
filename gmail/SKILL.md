---
name: gmail
description: >
  Gmail automation skill powered by gmail-agent (Go CLI). Handles email listing,
  sending, replying, deleting, AI-generated replies, rule-based classification,
  bulk historical classification, label management, filter management, and spam rescue.
  Trigger words: list emails, check mail, send email, reply, delete email, ai-reply,
  classify, bulk-classify, labels, filters, init, restore, spam, gmail.
license: MIT
---

# Gmail Agent Skill

## First-Run Detection (run on every invocation)

Before executing any email operation, check if gmail-agent is installed:

```bash
GMAIL_AGENT_DIR="${GMAIL_AGENT_DIR:-$HOME/gmail-agent}"
ls "$GMAIL_AGENT_DIR/run.sh" 2>/dev/null
```

**If not found:** Tell the user gmail-agent is not set up yet, then run the installer:

```bash
bash ~/.claude/skills/gmail/scripts/install.sh
```

This handles everything: clone → Google OAuth credentials → Anthropic API key →
compile → Gmail authorization. Do not proceed with email operations until it completes.

**If found:** Use `$GMAIL_AGENT_DIR/run.sh` for all commands below.

---

## Command Reference

```bash
# ── Daily Operations ────────────────────────────────────
./run.sh list                              # List unread emails (default 20)
./run.sh list -n 50                        # Specify count
./run.sh list -q "in:spam"                 # List spam
./run.sh list -q "in:trash"               # List trash
./run.sh list -q "label:Finance"          # By label
./run.sh list -q "from:github.com"        # By sender

./run.sh send --to <addr> --subject <subj> --body <body>
./run.sh reply <message-id> --body <body>  # Thread-aware reply

./run.sh delete <message-id>              # Move to trash
./run.sh delete --permanent <message-id>  # Permanently delete ⚠️

./run.sh ai-reply                          # Preview AI-generated replies
./run.sh ai-reply --dry-run=false          # Actually send
./run.sh ai-reply --dry-run=false -n 3    # Process up to 3 emails

# ── Real-time Classification (unread only) ───────────────
./run.sh classify                          # Preview (rules from rules.yaml)
./run.sh classify --dry-run=false          # Execute: label + archive/spam
./run.sh classify --dry-run=false -n 100  # Specify count

# ── Bulk Historical Classification ──────────────────────
./run.sh bulk-classify                     # Preview (searches full mailbox)
./run.sh bulk-classify --dry-run=false     # Execute
./run.sh bulk-classify --only Finance/Payment --only Finance/Bank  # Selective

# ── Spam Rescue ─────────────────────────────────────────
./run.sh restore <message-id> [id...]      # Restore from spam/trash to inbox
./run.sh restore -q "in:spam has:userlabels"  # Bulk restore by query

# ── Label Management ────────────────────────────────────
./run.sh labels list                       # List user labels
./run.sh labels create "Finance/Bank"     # Create a label
./run.sh labels delete "OldLabel"         # Delete label ⚠️ confirm required
./run.sh labels merge "OldName" "New/Name"  # Migrate emails + delete old label ⚠️
./run.sh labels apply labels-plan.yaml    # Execute a plan file

# ── Filter Management ───────────────────────────────────
./run.sh filters list                      # List all filters
./run.sh filters delete <id> [id...]       # Delete by ID ⚠️ confirm required
./run.sh filters apply filters-plan.yaml              # Preview plan
./run.sh filters apply filters-plan.yaml --dry-run=false  # Execute ⚠️
```

---

## Classification Architecture

### Confidence Tiers (`classify` — real-time, unread only)

```
sender domain match  →  HIGH confidence  →  execute action directly
                                             output tag: [category|sender]

subject keyword match  →  LOW confidence  →  send to AI for confirmation
  AI confirms  →  execute (spam downgraded to archive)   [category|subject+ai]
  AI rejects   →  fall back to full AI classification    [category|ai]
  no AI        →  spam auto-downgraded to archive        [category|subject]

no match at all  →  AI fallback classification            [category|ai]
```

**Core rule: spam action can only be triggered by high-confidence sender match.
Subject-only match caps at archive.**

### AI Intervention Points

| When | Trigger | What AI does |
|------|---------|-------------|
| During classify | subject-only match | Confirm classification (YES/NO) |
| During classify | no rule match | Full classification fallback |
| After classify | each batch | Quality review, flag suspicious items |

### `bulk-classify` Protections

- `-has:userlabels`: skips already-labeled emails, prevents cross-rule overwrites
- spam rules: **sender-only** queries — subject keywords excluded from spam matching
- Recommended execution order: Finance/Security (high confidence) → Project/DevOps → Ads

---

## Configuration Files

### `rules.yaml`

```yaml
# Order = priority. action: keep+important / keep / archive / spam
# sender match → high confidence, direct action
# subject match → low confidence, AI confirms; spam auto-downgraded to archive
categories:
  - name: Security/Alert
    action: keep+important
    sender:              # Strong signal: domain match, high confidence
      - accounts.google.com
      - security@apple.com
    subject:             # Weak signal: low confidence, needs AI confirmation
      - security alert
      - unusual activity

  - name: Finance/Payment
    action: keep
    sender:
      - apple.com
      - stripe.com
    subject:
      - invoice
      - receipt

  - name: Ads
    action: spam         # spam rules: bulk-classify uses sender-only query
    sender:              # Must have sender for spam to trigger
      - pinterest
      - mailchimp
    subject:             # In real-time classify: subject-only spam → downgraded to archive
      - unsubscribe
```

**Design principles:**
- `sender` is the strong signal — alone sufficient to trigger any action
- `subject` is the weak signal — alone caps at archive (spam requires AI confirmation)
- For spam rules, keep `sender` list as complete as possible

See `references/rules.example.yaml` for a full template.

### `labels-plan.yaml`

```yaml
create:
  - Finance/Bank
  - Security/Alert
delete:
  - OldLabel
merge:
  - from: OldName
    to: Finance/Bank
```

### `filters-plan.yaml`

```yaml
delete:
  - <filter-id>
create:
  - from: noreply@github.com
    label: Project/GitHub
    archive: true
```

---

## ⚠️ Safety Rules (mandatory)

**All destructive operations MUST call `AskUserQuestion` for user confirmation before executing.**

| Operation | Command | Must confirm |
|-----------|---------|-------------|
| Move to trash | `delete <id>` | ✅ |
| Permanent delete | `delete --permanent <id>` | ✅ state non-reversible |
| Delete label | `labels delete <name>` | ✅ |
| Merge labels (deletes old) | `labels merge` / `labels apply` with merge | ✅ |
| Delete filters | `filters delete <id>` / `filters apply` with delete | ✅ |

Confirmation example:
```
About to delete the following 3 Gmail filters. Confirm?
- ANe1BmgDb4... [from:newsletter@example.com] → TRASH
- ANe1Bmg03p... [list:digest@example.com] → TRASH
Options: [Confirm] [Cancel]
```

- For bulk deletes: show the **full list**, never just "N items"
- Cancel = stop and notify user

---

## Notes

- `config.json` and `token.json` contain account credentials — **never commit**
- `credentials.json` is the Google OAuth client ID — **never commit**
- AI reply and classify require Anthropic API key (set in `config.json`)
- `labels merge` migrates emails then deletes the source label — **irreversible**
