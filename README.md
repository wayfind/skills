# Claude Skills

A collection of reusable Claude Code skills for everyday automation.

## Skills

### [gmail](./gmail/)

Gmail automation powered by [gmail-agent](https://github.com/fanzhe/gmail-agent) — a Go CLI built on Google OAuth + Anthropic API.

**Capabilities:**
- List, send, reply, delete emails with Gmail query syntax
- AI-generated replies via Claude
- Rule-based email classification (`classify` + `bulk-classify`)
- Tiered confidence: sender = high, subject = low → AI confirmation
- Label and filter management
- Spam rescue with bulk restore

**Install:**
```bash
npx skills add wayfind/claude-skills --skill gmail
```

## Install All

```bash
npx skills add wayfind/claude-skills
```
