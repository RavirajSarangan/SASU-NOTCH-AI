# Nova landing page

Static site: `index.html`, `compare.html`, `styles.css`, `main.js`, `nova2.js` and `assets/`. No build step and no dependencies (Google Fonts only).

## Preview

```sh
cd landing
python3 -m http.server 8080
# open http://localhost:8080
```

## Deploy

Any static host works: Vercel (`vercel deploy landing`), Netlify, GitHub Pages or Cloudflare Pages.

## How the page works

- **Real screens.** `assets/screens/*.webp` are rendered by the app itself, not drawn by hand. Regenerate them after UI changes:
  ```sh
  scripts/landing_screens.sh
  ```
  It runs the debug build with `--landing-screens` (transparent background, approval buttons shown enabled), trims each panel and saves WebP files.
- **Real recordings.** `assets/video/*` (MP4, WebM and a WebP poster each) are screen recordings of the real app: real springs, the live Nova 2 renderer, real timing. Re-record after UI changes:
  ```sh
  scripts/record_landing.sh            # all clips: hero, approval, voice, dance, guard
  scripts/record_landing.sh voice      # just one
  ```
  It builds the debug app, quits the running Nova, and runs `--record-demo`. That starts only the notch window with demo data: no agent socket, automations, WhatsApp, microphone or Spotify. A script drives the same functions real clicks call, and ScreenCaptureKit records only Nova's own window over a drawn wallpaper and menu bar. Then ffmpeg encodes each clip, and the normal Nova is rebuilt and relaunched. The first run needs Screen Recording permission for Nova. Demo code exists only in debug builds.
  Videos play only while on screen. With reduced motion they show the poster and a play button.
- **The Mac frame.** The screen is 1200 app points wide, so a panel that is 640 pt wide in the app is `640 / 12` cqw on the page (`main.js`, `openShot`). The notch opens and closes between screens like the real one.
- **Nova, live.** `nova2.js` is the same character engine as the approved prototype (`docs/character/index.html`): springs, moods, fidgets, reactions, petting, dancing and the mood scenes. Keep the two in sync.
- **Sounds and the beat** are made live with WebAudio, only after a click.
- **Accessibility.** With `prefers-reduced-motion`, videos don't autoplay, Nova stays calm and screens appear without animation. Light and dark themes, plus a manual toggle.
- **Download link.** `releases/` is a placeholder. Point it at the real DMG once releases are published.
