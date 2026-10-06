# Nova 2: new character, premium design, pro features

**Your choices:** a new character drawn entirely in code, plus a usage and limits meter, diff previews, skins, and voice.

**Target:** v0.8 (character + usage + diffs), then v0.9 (skins + voice).

---

## 1. The new character: "Nova 2"

### Why draw it in code
Today Nova is 10 flat pictures with eyes painted on top. Moving from one mood to another swaps the whole picture, so nothing in between can move.

A character drawn from shapes can:
- move every part on its own
- stay sharp at any size
- change colour and outfit instantly (which is what makes skins possible)
- run at very low CPU

### Look: keep what makes Nova recognisable
- White, soft "fur" body and head, with a pearly gradient and a rim light.
- Cat ears with a blue-violet inner glow.
- A glossy black visor with Nova's live glowing eyes (the existing eye renderer is reused as is).
- Small paws, a round belly with the triangle chest light, and a curled tail.

**The premium touches (2.5D):**
- **Lighting:** soft top-left lighting, an ambient-occlusion shadow under the head, a specular shine on the visor that slides as the head turns.
- **Depth:** a contact shadow on the ground. When Nova looks sideways, the visor, eyes and ears shift a little, which reads as a real head turn.

### The rig (how it moves)
Nova is built from parts, and each part has joints:

| Part | Moves |
|---|---|
| Body | breathe (squash and stretch), lean, bounce |
| Head | tilt, turn (2.5D), nod |
| Ears (left and right) | perk, droop, twitch, flick independently |
| Paws (left and right) | rest, wave, type, cover eyes, celebrate |
| Tail | swish, curl, wag speed |
| Visor | eyes (existing), shine, glow colour |
| Chest light | colour and pulse by mood |

**Motion design:**
- **Every mood is a set of joint targets.** For example, *thinking* tilts the head, raises one paw to the chin and slows the tail swish; *happy* perks the ears, wags the tail and does a small hop.
- **Moods blend smoothly.** Nova eases between targets (the same approach as today's eyes), so a change never pops.
- **Follow-through makes it feel alive.** Ears and tail lag behind the head on soft springs, so a hop makes the ears bounce and a turn makes the tail sway.
- **Idle life, kept calm:** breathing, an ear twitch every few seconds, a slow tail swish, a blink, and looking at your cursor. After 5 minutes Nova curls up to sleep.
- **Reactions stay** (hop, shake, pop, nod), now driving real joints instead of moving the whole picture.
- **New gestures:** a wave when you open the notch, a "typing" paw motion while agents code, a paw over the visor when an error happens, and a confetti cheer when a task is done.

### Engineering
- **`NovaKit/Character/Rig.swift`:**
  - `RigPose` holds all joint values, and can blend or ease.
  - `RigPose.target(for: mood)`.
  - Follow-through springs.
  - Pure math, unit-tested: it settles, never overshoots too far, and stays inside each joint's limits.
- **`Character/NovaRigRenderer.swift`:** draws the parts with SwiftUI Canvas paths and gradients, back to front (tail, body, paws, head, ears, visor, eyes).
  - One draw call per frame.
  - 30 fps in the notch, 60 fps in big views.
  - Paused when hidden.
- **`NovaCharacterView`** gains a `style: .classic | .nova2` switch. Your original art stays available as "Classic" in Settings until Nova 2 is approved.
- **No Metal shaders** (this build has no Xcode Metal compiler). Gradients and blur give the soft 3D look.
- **Landing page:** the same character is drawn in the browser with canvas, so the website matches the app exactly. There are no more baked PNGs.

### How we'll get the look right
1. A **turnaround sheet**: front, three-quarter, side, sleeping, plus all 18 moods, rendered to PNG via `--snapshot`. You review it before any animation work. Two revision rounds are expected.
2. A **motion sheet**: short recordings (frame strips) of idle, hop, wave, thinking and sleep, for your review.
3. Only then switch the default to Nova 2.

---

## 2. Pro features

### a) Usage and limits meter (v0.8)
- **Source:** your local Claude Code logs (`~/.claude/projects/**/*.jsonl` record input, output and cache tokens per message, with timestamps) and Codex's `~/.codex/sessions`. Nova reads only the usage numbers and timestamps; no message text and no keys.
- **Shows:**
  - tokens used in the current 5-hour window and this week
  - a burn rate (tokens per hour)
  - a "you'll hit the limit around 4:20 pm" estimate
  - a per-project breakdown
  - an estimated cost for API-key users (prices set in Settings)
- **Alerts** at 80% and 95% of a limit you set (plans differ, so you choose your limit; there are presets).
- **UI:**
  - a thin usage ring around the agent logo in the notch
  - a Usage card on Home
  - a detail view with a 7-day chart
- Parsing and window maths live in NovaKit with tests (log fixtures).

### b) Diff preview in approvals (v0.8)
- **Hook:** the hook already receives the edit (`old_string` / `new_string`, or the full `content` for Write). It forwards a capped preview: up to 200 lines, secrets masked (keys, tokens, `.env` values).
- **Permission panel:**
  - a red/green line diff with the file name and the +/− counts
  - scrollable, and expandable to a larger view
  - multi-edit shows each change
- **Risk upgrade:** edits to `.env`, CI config, `package.json` scripts or lockfiles are marked higher risk, with the reason shown.
- **Tests:** diff builder, line counts, masking, size cap.

### c) Skins and outfits (v0.9)
Because Nova 2 is drawn in code, a skin is just data: a palette plus optional accessories.

| Skin | Look |
|---|---|
| Aurora (default) | white fur, blue-violet glow |
| Midnight | charcoal fur, cyan glow |
| Sakura | pale pink, warm white eyes |
| Neon | black, magenta and green rim lights |
| Gold | pearl and gold trim, for celebrations |

- **Accessories:** headphones (shown automatically while Spotify plays), glasses (shown during code review), a scarf (seasonal), a party hat (on birthdays and releases), a hoodie.
- **Unlocks:** some skins unlock through use (for example, 100 approved commands unlocks Gold). Optional and playful; everything can also be picked freely.
- **Settings:** a skin gallery with a live preview. The landing page shows the skins too.

### d) Voice, "Hey Nova" (v0.9)
- **Start with push-to-talk:** hold ⌥ Space or click the mic. Speech is recognised **on the device** (Apple Speech, on-device only), so audio never leaves the Mac.
- **What you can say:**
  - "What are my agents doing?"
  - "Deny that."
  - "Read the brief."
  - "Play music."
  - "How much usage is left?"
  - "Scan security."
  - Anything else goes to your AI chat.
- **Nova answers out loud** with a system voice you pick. Its visor eyes and chest light pulse with the voice, and it gestures while speaking.
- **Safety:**
  - Voice can never *allow* a risky command; it can only deny it.
  - Anything that changes state asks "Should I…?" on screen first.
- **Later:** a hands-free wake word, opt-in only, with a clear indicator while listening.
- **Permissions:** Microphone and Speech Recognition, requested only when you first use voice.

---

## 3. Order of work

| Step | What | You review |
|---|---|---|
| 1 | Rig maths + renderer, front view, idle | turnaround sheet v1 |
| 2 | All 18 moods + gestures + follow-through | motion sheet |
| 3 | Usage meter (parsing, ring, card, alerts) | live numbers from your logs |
| 4 | Diff preview in approvals | a real Claude edit request |
| 5 | Nova 2 becomes default; landing page canvas version | app + site |
| 6 | Skins + accessories + gallery | skin sheet |
| 7 | Voice push-to-talk + spoken replies | try it live |
| 8 | Re-run `docs/COMPARISON.md`, bump to v0.9 | updated scorecard |

**Quality bar for every step:**
- tests pass
- idle CPU stays at or under 5%
- Reduce Motion is respected
- snapshots are reviewed
- a commit after each step

## 4. Risks and how we handle them
- **The code-drawn look might not match your taste at first.** That's why the turnaround sheet comes before animation work, and Classic stays available.
- **Usage limits aren't published as exact numbers** and vary by plan. Nova shows your real usage and lets you set the limit, rather than guessing.
- **Speech recognition languages:** on-device recognition supports English well; Tamil support depends on macOS. Nova falls back to typing if your language isn't available offline.
