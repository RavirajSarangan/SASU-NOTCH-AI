# Nova roadmap

**Guiding principles**
- Local first. Audio, security data and agent activity stay on the Mac.
- Never approve anything on the user's behalf. Voice and automations can deny, never allow.
- Undo for every automatic action.
- Calm until something matters. Big motion and sound only for events.
- Measured, not assumed: every release re-checks CPU, crashes and the comparison.

Each release starts with its own plan and ends by updating [COMPARISON.md](COMPARISON.md).

---

## Where Nova is now (v0.8, 5 Oct 2026)

**Agents**
- Many sessions at once; chips adapt to the panel and extra sessions go under "+N".
- Diff preview before allowing an edit (red/green, +N −M, secrets masked).
- Claude's multiple-choice questions answered in the notch.
- Jump to the right terminal; subagent badges.

**Safety**
- Two-click approvals for high risk; always-deny list; Guard mode while away.
- Nova Guard: posture checks, intrusion alerts, startup items, SSH keys, profiles, cron, sudoers, shell files; undoable auto-fixes; admin fixes on click.
- Accurate microphone check (other apps only) and camera check.

**Nova 2 character**
- Drawn in code with springs, 18 moods, fidgets, reactions, petting, skins.
- Animated mood scenes behind Nova (aurora, code rain, music, Guard scan, night sky…).
- Dances on the real beat of Spotify or Music (on-device), or a steady groove.

**Hey Nova (voice)**
- Hold ⌥ Space, click the mic, or the optional wake word.
- On-device recognition only; English, Tamil script and Tanglish commands.
- Status, deny, music, security scan, brief, open app, volume, time and date, jokes, dance; anything else goes to your AI provider.

**Your day**
- Morning brief, WhatsApp greetings and reply drafts, Spotify, launcher, service status, chat with cloud or local models.

**Reliability fixed this release**
- A sound-engine exception that froze the main queue (empty Home, stalled timers, crashes).
- Keychain reads, AppleScript, CoreAudio and device checks moved off the main thread.
- Stable local signing, so permissions survive rebuilds.
- Live-session CPU down from ~40% to ~16%.

**Added after v0.8 (5 Oct 2026)**
- Voice that controls the Mac:
  - open, quit and switch apps, and "Hey Safari"
  - websites; Google, YouTube and Spotify search; browser tabs
  - typing; clicking buttons by name; mute; timer; screenshot; lock
  - risky buttons need a mouse click
- Anything else goes to the AI, which either answers or picks one of those safe actions.
- Free AI: Groq and OpenRouter; automatic fallback when a provider is busy (the 503 error).
- "Hey Nova" works reliably:
  - no deaf periods
  - a crash on the first mic click is fixed
  - macOS speech services no longer count as "an app using the mic", which caused the alert spam

**Added 6 Oct 2026**
- **Talk naturally:**
  - follow-up questions without "Hey Nova"
  - conversation context
  - interrupt Nova with "Hey Nova" or "stop"
  - find files by voice
  - clipboard help: summarise, explain, fix, shorten, translate
- **WhatsApp by voice:** read back, then sent on "send"; scheduled messages.
- **"Check my system":** threats plus health.
- **Plans:** multi-step jobs that pause before risky steps; an action log.
- **Calendar and reminders:** "what's next?"; "remind me at 5 to…"; a meeting nudge 5 minutes before, with a join link.
- **Routines** ("start my work day"; build them in Settings or by voice) and **Apple Shortcuts** by name.
- **Usage and limits meter** for Claude Code and Codex: 5-hour and weekly windows, burn rate, alerts at 80% and 95%, a top-bar ring.
- **Landing page:** real recordings of the app.

**Still open from this release**
1. **WhatsApp test mode** is on by default. Turn it off in Settings → Automations → WhatsApp to send for real; drafts always need a click.
2. **Base CPU while a session is live is ~16%,** the same as before Nova 2. Target ≤ 8% (see v0.9).
3. **Tamil speech recognition** depends on macOS offering it offline. Nova checks and falls back to English.

---

## Gaps against other notch apps

| Gap | Who has it | Why it matters to users | Plan |
|---|---|---|---|
| Usage and plan limits | Vibe Island, CodeIsland, Ping Island, Coucou | Avoid hitting a limit mid-task | v0.9 |
| Signed, notarized, auto-updating app | Most paid apps | Install without warnings; get fixes | v0.9 |
| More agents (OpenCode, Copilot CLI, Kimi) and one-click hook install | Vibe Island (~30 agents) | Works with whatever you use | v0.9 |
| Desktop companion mode | Coucou, Notchi | Nova on any Mac, not only in the notch | v1.0 |
| Phone or watch alerts | CodeIsland | Approve or know from anywhere | v1.0 |
| Remote agents over SSH | Ping Island | Servers and cloud dev boxes | Later |

Nova already leads on security, diff previews, voice, the live character and personal automations.

---

## v0.9 "Trust and speed" (next)

| Feature | User value | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Usage and limits meter**: parse Claude Code / Codex local logs (numbers only); 5-hour and weekly windows; burn rate; "you'll hit the limit around 4:20 pm"; ring in the notch, Home card, alerts at 80/95% | Never get cut off mid-task | M | Log formats change: parsers tested on fixtures, fail quietly | Matches each tool's own reading within 5% |
| **Signed + notarized build, Sparkle auto-update, /Applications install, login item** | Installs without scary warnings; fixes arrive automatically | M | Needs an Apple Developer ID (user decision, $99/yr) | Zero Gatekeeper prompts on a fresh Mac |
| **One-click hook installers** for every agent, with a dry run and backup; Settings → Agents status | Setup in a minute, nothing broken | S | Editing other tools' configs: always dry run and back up first | 100% of supported agents detected and installable |
| **More agents**: OpenCode, Copilot CLI, Kimi | Works with what users run | S | Each has its own hook format | Live sessions show for each |
| **CPU to ≤ 8% during sessions**: find the remaining cost (render commits, observation churn) | Cooler, quieter laptop | M | Profiling is noisy: measure with settled CPU time | ≤ 8% average over 20 s with a live session |
| **Per-project rules** ("always allow `npm test` in portfolio") | Fewer interruptions, still safe | S | Rule scope must be narrow: exact command + project | 30% fewer approval prompts in a normal day |
| **Guard weekly report + Supabase RLS advisor** | Know you're safe; catch open databases | M | Read-only checks only | Report every Monday; RLS issues listed with fix SQL |
| **Accessories on Nova 2**: headphones while music plays, glasses during code review, party hat on releases | Delight; Nova feels aware | S | Keep them subtle | Shown automatically, togglable |

## v1.0 "Companion" (the Jarvis track)

| Feature | User value | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Desktop mode**: drag Nova out of the notch; it floats (Orbit body), dangles while dragged, remembers its spot; double-click to return | Nova on any Mac and any screen | M | Must never cover important UI: click-through edges | Works on Macs without a notch |
| **Session sparks in the app**: each live session orbits Nova; the one that needs you pulses and Nova points at it | Find the right session instantly | S | Busy screens: max 4 sparks | Click a spark → right terminal in < 1 s |
| **Mac actions library** (typed, confirmed): open a project, start or stop an agent, reminders, Shortcuts, files | Ask once, done | M | Anything that changes state shows "Doing X, say cancel" | No action runs without a visible confirmation |
| **Memory of you** (local, encrypted, editable): projects, routines, people; "forget this" | Answers that know your context | L | Privacy: local only, viewable, deletable | Every memory visible in Settings; nothing syncs |
| **Proactive help** with quiet hours: morning plan, "agent stuck for 10 min", "3 approvals waiting", "you've coded 3 hours, stretch?" | Help before you ask | M | Nagging: rate-limited, one tap to mute each kind | Under 5 nudges a day by default; < 10% muted |
| **Phone alerts** through your own ntfy or Pushover topic (opt-in) | Know when you're away | S | Never send code or secrets: titles only | Alert within 5 s; deny from the phone |
| **File drop on the notch**: drop a file and ask about it | Faster than opening chat | S | Large files: only text sent, with a size cap | Answers within one round trip |
| **Custom shortcuts**: open chat, jump to terminal, next session, mute, desktop mode | Keyboard-first users | S | Conflicts with other apps: show a warning | All actions rebindable |

## v1.1 and later

- Remote agents over SSH (a small relay on the server, same socket protocol).
- Team mode: shared approvals for a team's agents.
- A plugin API for custom notch panels.
- Nova on the web page and in the app share one character engine (already true for the landing page).

---

## Future plan (planned only, nothing built yet)

Ideas collected on 5 Oct 2026. They are ordered by value to you, and each lists its effort (S, M or L), risk and how we'll know it works. Same rules as everything else: on the Mac first, voice never approves, and anything risky waits for a click.

### A. Talking to Nova feels natural
| Feature | Why you'd want it | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Follow-up without the wake word**: after a reply, Nova keeps listening for 6 s ("…and open Safari") | Conversation, not commands | S | False triggers: only within 6 s and only while the panel is open | 80% of follow-ups work without repeating "Hey Nova" |
| **Interrupt Nova** by talking over it (barge-in) | No waiting for long replies | M | Nova hearing itself: pause recognition while speaking unless your voice is louder | Interrupt works in under 0.5 s |
| **Your voice only**: on-device speaker check, so the TV or other people can't command Nova | Safety and fewer false wakes | L | Accuracy differs by mic: fall back to "anyone" with a warning | Under 1 false wake per day |
| **Small wake-word engine** (a tiny on-device model in place of full recognition) | Less CPU and battery while listening | M | Model licence and accuracy | Wake listening under 2% CPU |
| **Better Tamil offline** (a local Whisper model when macOS has no Tamil) | Tamil works on every Mac | M | Model size (~150 MB): optional download | Tamil commands work offline |
| **Natural voices** (Personal Voice / premium voices; per-language voice picker) | Nova sounds less robotic | S | Some voices need a download | Voice chosen in onboarding |

### B. Jarvis actions
| Feature | Why you'd want it | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Routines**: "start my work day" opens the project, VS Code, Slack and a focus playlist, and turns on Do Not Disturb | One sentence instead of ten clicks | M | Each step shown before it runs; stop any time | A routine is set up in under 2 minutes |
| **Run Apple Shortcuts by name** ("run Log water") | Anything Shortcuts can do, by voice | S | Shortcuts can do risky things: ask once per shortcut | Every Shortcut is listed and runnable |
| **Calendar and reminders** (EventKit): "what's next?", "remind me at 5 to call Amma", join link 5 minutes before meetings | Daily assistant basics | M | Calendar privacy: read only what's needed, on the Mac | Reminder created by voice in one sentence |
| **Find files** (Spotlight): "open the invoice PDF from last week" | No more digging in Finder | S | Wrong file: show the top 3 to pick | Right file in the top 3 for 80% of requests |
| **"What's on my screen?"**: a screenshot to a vision model (opt-in each time) | Explain an error, summarise a page | M | Privacy: the screenshot is shown before sending, never saved | Answer in under 5 s |
| **Clipboard help**: "summarise what I copied", "translate this to Tamil" | Fast everyday AI | S | Clipboard may hold secrets: masked like diffs | Works on text up to 20k characters |
| **Voice to agents**: "tell Claude to run the tests" types into that agent's terminal; never Enter on approval prompts | Drive agents hands-free | M | Must never answer an approval: block when an approval is pending | Instruction lands in the right session 95% of the time |
| **Action log with undo**: every voice action listed, with undo where possible (reopen a closed tab, restore a closed app) | Trust | S | Not everything can be undone: say so | Every action appears in the log |
| **Per-app voice permissions**: choose which apps voice may click or type in | Control | S | None | Settings list with per-app toggles |

### C. Proactive (helps before you ask)
| Feature | Why you'd want it | Effort | Risk | Success metric |
|---|---|---|---|---|
| **End-of-day summary**: what agents did, files changed, tests run | Know your day at a glance | M | Long sessions: summarise locally first | Read in under 30 s |
| **Focus timer (Pomodoro)** with Nova reacting and breaks suggested | Healthy coding | S | Nagging: easy to turn off | Under 5% of breaks muted |
| **Battery, disk and Wi-Fi nudges** ("battery 10%, plug in before the agent finishes") | Avoid surprises | S | Noise: only when it matters | Under 3 nudges a day |
| **Quiet hours and Focus-mode awareness** | Nova stays silent in meetings | S | None | No sounds during Focus |

### D. Free and private AI
| Feature | Why you'd want it | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Auto-pick the fastest free provider** (measured latency and errors per provider) | The best free answer, automatically | S | Provider limits change: re-measure daily | Median voice answer under 2 s |
| **One-click Ollama setup** (detect, suggest a model that fits your RAM, pull with progress) | Offline AI without the terminal | M | Disk space: show the size first | Set up in under 3 minutes |
| **Usage and limits meter** (already planned for v0.9), including free-tier counts | Never hit a limit by surprise | M | See v0.9 | See v0.9 |

### E. Nova as a character
| Feature | Why you'd want it | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Accessories** (headphones with music, glasses in review, party hat on release; already in v0.9) | Delight | S | Subtle only | — |
| **Achievements and mini-games** (streaks, "100 approvals safely denied", a tiny notch game while agents run) | Fun while waiting | M | Distraction: only while idle | Opt-in rate |
| **Skins gallery and custom colours** | Make Nova yours | S | None | — |
| **Birthdays and festivals** (Pongal, Diwali, New Year themes) | Feels personal | S | None | — |

### F. Platform
| Feature | Why you'd want it | Effort | Risk | Success metric |
|---|---|---|---|---|
| **Signed and notarised build, auto-update, login item** (v0.9) | Installs cleanly; runs at startup so automations never miss | M | Needs an Apple Developer ID | Zero Gatekeeper prompts |
| **Tamil interface** (full UI translation) | Native-language users | M | Translation quality: review by a native speaker | 100% of strings translated |
| **VoiceOver and keyboard access** throughout | Accessibility | M | None | Every control reachable |
| **iPhone companion** (alerts and deny from the phone; v1.0) | Away from the desk | L | Never send code or secrets | Alert in under 5 s |

**Suggested order:** A1 follow-ups, B9 per-app permissions and B8 action log (trust first), then B1 routines, B3 calendar, B2 Shortcuts, D1 auto-pick free provider, C1 end-of-day summary. Then the larger items: A3 your-voice-only, B5 screen questions, F4 iPhone.

---

## How each release is checked

1. The test suite passes (kept private); zero build warnings.
2. Snapshots reviewed (`--snapshot`), including busy layouts.
3. Live checks: `--capture-home` with two sessions, `--ask-nova` voice commands (no music commands in automated runs).
4. Release app runs 2 minutes with live events and no crash report; settled CPU measured.
5. The comparison and the landing page are updated, and the landing screens are re-rendered (`scripts/landing_screens.sh`).
