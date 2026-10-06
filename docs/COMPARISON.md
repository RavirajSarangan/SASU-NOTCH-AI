# Nova vs other apps

**Last compared: 2026-10-05, against Nova v0.7 (in progress).** Re-run this comparison before every release (see the [release checklist](#release-checklist)).

Sources: each product's own site and the [vibeisland.app comparison](https://vibeisland.app/best-ai-agent-notch-apps/) (2026). Competitor claims are as those pages describe them; check them again before quoting.

## 1. AI-agent notch apps

| Capability | Vibe Island | CodeIsland | Ping Island | Claude Pulse | ClaudeNotch | Notchi | Coucou | **Nova** |
|---|---|---|---|---|---|---|---|---|
| Agents supported | ~30 | several | several | Claude only | Claude only | several | 5 | **6** (Claude, Codex, Cursor, Gemini, Antigravity, VS Code) + any tool via socket |
| Several sessions at once | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **✓** (v0.7) |
| Jump to terminal | ✓ (20+ terminals) | ✓ | ✓ | – | limited | limited | ✓ | **✓** (host app detected by the hook, v0.7) |
| Approve or deny in the notch | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ + always allow | **✓**, two-step for high risk |
| Always-deny dangerous commands | – | – | – | – | denials | – | **✓** (reverse shells, `curl \| sh`, Keychain dumps…) |
| Usage and limits meter | ✓ | ✓ | ✓ | ✓ | ✓ + spending caps | – | ✓ (5-hour + weekly) | ✗ (planned for v0.8) |
| Subagent tracking | – | ✓ | – | – | – | – | – | **✓** (count badge) |
| Diff preview in approvals | – | – | – | – | ✓ | – | ✓ (+N −M, tap) | ✗ (planned for v0.9) |
| Remote / SSH agents | – | – | ✓ | – | – | – | – | ✗ (later) |
| Phone or watch companion | – | ✓ | – | – | – | – | – | ✗ (v1.0, via ntfy/Pushover) |
| Mascot with moods | – | – | – | – | – | pixel sprites | Mochi + wardrobe | **✓** (18 moods, poses, reactions) |
| Sounds | 8-bit per event | – | – | – | – | – | 28 sounds | **✓** (3 packs, per mood and per event) |
| Mac security monitoring | – | – | – | – | – | – | – | **✓** (Nova Guard + safe auto-fix) |
| Personal automations | – | – | – | – | – | – | – | **✓** (WhatsApp, morning brief) |
| Service status (GitHub, Vercel…) | – | – | – | – | – | – | ✓ (7) | **✓** |

**Coucou extras worth adopting (our own design, not its assets):**
- answering agent questions in the notch
- "+N −M" line counts
- click reactions
- desktop companion mode
- file drop
- local models
- custom shortcuts

See `NOVA_2_PLAN.md`.

**Where Nova is behind:**
- usage and limits
- diff previews
- breadth of agents
- remote agents
- phone companion

**Where Nova is unique:** it combines an agent monitor, a security guard and a personal assistant, with a character people like.

## 2. Personal assistants ("Jarvis" track)

| Capability | Raycast AI | ChatGPT desktop | Claude desktop | Apple Intelligence / Siri | **Nova** |
|---|---|---|---|---|---|
| Always-visible presence | launcher hotkey | hotkey window | app window | system-wide | **notch** |
| Voice | – | ✓ | ✓ (mobile) | ✓ | ✗ (v1.0: on-device "Hey Nova") |
| Acts on the Mac | extensions | app/screen context | tools/connectors (MCP) | App Intents | partial: launcher, Spotify, WhatsApp (planned: typed action registry) |
| Remembers you | – | memory | memory/projects | personal context | ✗ (v1.0: local encrypted memory) |
| Proactive | – | scheduled tasks | – | suggestions | partial: morning brief, approval nudges |
| Watches coding agents | – | – | – | – | **✓** |
| Guards the Mac | – | – | – | – | **✓** |

**Best ideas to adopt:**
- Raycast's instant actions
- ChatGPT's voice mode
- Claude's tool connectors
- Apple's on-device privacy

Nova should stay local-first and keep its permission discipline.

## Scorecard

Each area is scored 0–5 on how well Nova covers it today. Re-score it after each release.

| Area | v0.6 | v0.7 | v0.8 (5 Oct 2026) | Target for v1.0 |
|---|---|---|---|---|
| Agent monitoring | 3 | 4 | 4 (no usage meter yet) | 5 |
| Approval safety | 4 | 5 | 5 (diff preview, questions in the notch) | 5 |
| Mac security | 0 | 4 | 4 | 4 |
| Character and delight | 3 | 5 | 5 (Nova 2, mood scenes, dancing) | 5 |
| Personal assistant | 2 | 2 | 3 (on-device voice, English + Tamil) | 4 |
| Polish and performance | 3 | 4 | 4 (freeze fixed; live-session CPU still ~16%) | 5 |

## Release checklist

1. Re-check each competitor's site for new features, and update the tables above with the date.
2. Re-score Nova honestly; mark anything still planned with ✗.
3. Move adopted ideas into [ROADMAP.md](ROADMAP.md).
