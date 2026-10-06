// Nova landing page. No dependencies (nova2.js is Nova's own character engine).
(() => {
  "use strict";
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  // ---------- Theme ----------
  const root = document.documentElement;
  const saved = (() => { try { return localStorage.getItem("nova-theme"); } catch { return null; } })();
  if (saved) root.dataset.theme = saved;
  $(".theme-toggle")?.addEventListener("click", () => {
    const dark = root.dataset.theme ? root.dataset.theme === "dark" : !matchMedia("(prefers-color-scheme: light)").matches;
    root.dataset.theme = dark ? "light" : "dark";
    try { localStorage.setItem("nova-theme", root.dataset.theme); } catch { /* private mode */ }
  });

  // ---------- Small UI sounds (the app's "Soft" pack) ----------
  const N = { A4: 440, C5: 523.25, E5: 659.25, G5: 783.99, A5: 880, C6: 1046.5, E6: 1318.51, G6: 1567.98 };
  const CUES = {
    success: [[N.C6, 0.07], [N.E6, 0.07], [N.G6, 0.2]],
    error: [[N.E5, 0.18, N.C5], [N.A4, 0.18]],
    listening: [[N.C6, 0.09, N.E6]],
    notification: [[N.E6, 0.07], [N.G6, 0.13]],
  };
  let audio;
  function play(name) {
    const tones = CUES[name];
    if (!tones) return;
    try { audio ??= new (window.AudioContext || window.webkitAudioContext)(); if (audio.state === "suspended") audio.resume(); } catch { return; }
    let t = audio.currentTime + 0.01;
    for (const [f, d, end] of tones) {
      const o = audio.createOscillator(), g = audio.createGain();
      o.type = "sine"; o.frequency.setValueAtTime(f, t); if (end) o.frequency.exponentialRampToValueAtTime(end, t + d);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.12, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
      o.connect(g).connect(audio.destination); o.start(t); o.stop(t + d + 0.02);
      t += d + 0.02;
    }
  }

  // GitHub stars in the nav (quietly skipped if the API can't be reached).
  const stars = $("[data-stars]");
  if (stars) {
    fetch("https://api.github.com/repos/RavirajSarangan/SASU-NOTCH-AI")
      .then(r => (r.ok ? r.json() : null))
      .then(repo => {
        if (repo && Number.isFinite(repo.stargazers_count)) {
          stars.textContent = repo.stargazers_count.toLocaleString();
          stars.hidden = false;
        }
      })
      .catch(() => {});
  }

  // Menu-bar clocks
  const clock = () => new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  $$("[data-clock]").forEach(el => { el.textContent = clock(); });

  // ---------- Compare page: filter rows by topic ----------
  const filters = $$(".filters button");
  filters.forEach(btn => btn.addEventListener("click", () => {
    filters.forEach(b => b.setAttribute("aria-pressed", String(b === btn)));
    const want = btn.dataset.filter;
    $$("#matrix tbody tr").forEach(tr => { tr.hidden = want !== "all" && tr.dataset.group !== want; });
  }));

  const Nova2 = window.Nova2;
  if (!Nova2) return;   // pages without the character (compare.html)

  // ---------- Real screens in the notch ----------
  // Natural sizes are @2x pixels; the screen is 1200 app points wide, so 1 pt = 1/12 cqw.
  const SHOTS = {
    "home": [1280, 721], "approval-diff": [1280, 569], "approval-risk": [1280, 469], "question": [1280, 477],
    "session": [1280, 716], "compact": [916, 168], "voice-reply": [956, 236], "voice-listening": [956, 236],
    "dance": [1280, 721], "brief": [1280, 722],
  };
  const cq = px => `${(px / 2 / 12).toFixed(2)}cqw`;
  function openShot(mask, img, key, { instant = false } = {}) {
    const [w, h] = SHOTS[key];
    const apply = () => {
      img.src = `assets/screens/${key}.webp`;
      img.style.width = cq(w);
      mask.style.width = cq(w);
      mask.style.height = cq(h);
      mask.style.borderRadius = "0 0 2.2cqw 2.2cqw";
      mask.classList.remove("closed");
    };
    if (instant || reduceMotion) { apply(); return; }
    // Close into the camera housing, swap, then open: like the real notch.
    mask.classList.add("closed");
    mask.style.width = "15.4cqw"; mask.style.height = "2.7cqw"; mask.style.borderRadius = "0 0 1.2cqw 1.2cqw";
    clearTimeout(mask._t);
    mask._t = setTimeout(apply, 420);
  }

  // ---------- Live characters and scenes ----------
  const lives = [];   // { nova, el, visible, music() }
  const scenes = [];  // { scenes, el, visible, name() }
  function addLive(el, opts, music = () => null) {
    if (!el) return null;
    const nova = new Nova2.LiveNova(el, opts);
    const entry = { nova, el, visible: true, music };
    lives.push(entry);
    return entry;
  }
  function addScene(canvas, name) {
    if (!canvas) return null;
    const entry = { scenes: new Nova2.Scenes(canvas), el: canvas, visible: true, name };
    scenes.push(entry);
    return entry;
  }
  const io = new IntersectionObserver(es => es.forEach(e => {
    for (const x of [...lives, ...scenes]) if (x.el === e.target) x.visible = e.isIntersecting;
  }));

  // Brand heads (static drawing).
  $$("[data-nova-head]").forEach(el => { el.innerHTML = Nova2.nova({ crop: "head", detail: "min", noFx: true, still: true }); });

  // ---------- Real recordings ----------
  // Every video is a screen recording of the real app (scripts/record_landing.sh).
  // Videos play only while on screen; with reduced motion they show their
  // poster and a play button instead.
  const setClip = (video, clip) => {
    if (video.dataset.clip === clip) return;
    video.dataset.clip = clip;
    video.poster = `assets/video/${clip}.webp`;
    const [webm, mp4] = video.querySelectorAll("source");
    webm.src = `assets/video/${clip}.webm`;
    mp4.src = `assets/video/${clip}.mp4`;
    video.load();
  };
  const playIfShown = video => { if (!reduceMotion && video._shown) video.play().catch(() => {}); };
  const videoIO = new IntersectionObserver(es => es.forEach(e => {
    e.target._shown = e.isIntersecting;
    e.isIntersecting ? playIfShown(e.target) : e.target.pause();
  }), { threshold: 0.25 });
  $$("video.screen-video").forEach(v => {
    if (reduceMotion) { v.removeAttribute("autoplay"); v.controls = true; }
    videoIO.observe(v);
  });

  // ---------- Hero: tabs switch recordings; each plays once, then the next ----------
  const heroVideo = $("[data-hero-video]"), tabs = $$(".hero-tabs [data-clip]");
  const heroOrder = tabs.map(t => t.dataset.clip);
  let heroShot = "home", heroUser = false;
  const heroWall = null;
  if (heroVideo) heroVideo.dataset.clip = "hero";
  function showHero(clip, { user = false } = {}) {
    if (!heroVideo) return;
    heroShot = clip;
    tabs.forEach(t => t.setAttribute("aria-selected", String(t.dataset.clip === clip)));
    setClip(heroVideo, clip);
    heroVideo.loop = heroUser || user;
    if (user) { heroUser = true; heroVideo.loop = true; $(".hero-tabs")?.classList.add("paused"); }
    playIfShown(heroVideo);
  }
  tabs.forEach(t => t.addEventListener("click", () => showHero(t.dataset.clip, { user: true })));
  heroVideo?.addEventListener("ended", () => {
    if (!heroUser) showHero(heroOrder[(heroOrder.indexOf(heroVideo.dataset.clip) + 1) % heroOrder.length]);
  });
  heroVideo?.addEventListener("loadedmetadata", () => {
    $(".hero-tabs")?.style.setProperty("--dwell", `${Math.round(heroVideo.duration * 1000)}ms`);
  });

  // ---------- Tour: steps drive the sticky Mac (recording when there is one, else a real still) ----------
  const tourMask = $("[data-tour-mask]"), tourImg = $("[data-tour-shot]"), tourVideo = $("[data-tour-video]");
  let tourShot = "home";
  addScene($(".tour .wall"), () => tourShot === "session" ? "code" : tourShot.startsWith("approval") ? "warning" : tourShot === "question" ? "thinking" : "aurora");
  const showTour = step => {
    const clip = step.dataset.clip;
    tourShot = step.dataset.shot;
    if (tourVideo) {
      tourVideo.hidden = !clip;
      if (clip) { setClip(tourVideo, clip); playIfShown(tourVideo); } else tourVideo.pause();
    }
    if (tourMask) {
      tourMask.hidden = Boolean(clip);
      if (!clip) openShot(tourMask, tourImg, tourShot);
    }
  };
  if (tourVideo) tourVideo.dataset.clip = "hero";
  if (tourMask) { openShot(tourMask, tourImg, "home", { instant: true }); tourMask.hidden = true; }
  const steps = $$(".step");
  const stepIO = new IntersectionObserver(es => es.forEach(e => {
    if (!e.isIntersecting) return;
    steps.forEach(s => s.classList.toggle("active", s === e.target));
    if (e.target.dataset.shot !== tourShot || e.target.dataset.clip !== tourVideo?.dataset.clip) showTour(e.target);
  }), { rootMargin: "-45% 0px -45% 0px" });
  steps.forEach(s => stepIO.observe(s));

  // ---------- Meet Nova ----------
  let dancing = false;
  const meet = addLive($("[data-meet-nova]"), { viewBox: "-30 -34 300 284", drag: true, sound: true, dance: true },
    () => (dancing ? Nova2.Music.update() : null));
  const meetWall = addScene($("[data-meet-stage] .wall"), () => meet ? Nova2_sceneFor(meet.nova) : "aurora");
  function Nova2_sceneFor(n) { return n.dancing ? "music" : (Nova2.sceneFor ? Nova2.sceneFor(n.state?.mood || n.mood, n) : "aurora"); }

  const moodsEl = $("[data-moods]"), skinsEl = $("[data-skins]");
  const MOODS = ["idle", "happy", "thinking", "coding", "listening", "surprised", "warning", "error", "sleeping", "excited", "confused", "success", "dizzy"];
  if (moodsEl && meet) {
    for (const m of MOODS) {
      const b = document.createElement("button");
      b.type = "button"; b.className = "chip"; b.textContent = m[0].toUpperCase() + m.slice(1);
      b.setAttribute("aria-pressed", String(m === "idle"));
      b.addEventListener("click", () => {
        stopDance();
        meet.nova.setMood(m);
        $$(".chip", moodsEl).forEach(x => x.setAttribute("aria-pressed", String(x === b)));
      });
      moodsEl.append(b);
    }
  }
  if (skinsEl && meet) {
    for (const [k, s] of Object.entries(Nova2.SKINS)) {
      const b = document.createElement("button");
      b.type = "button"; b.className = "chip";
      b.innerHTML = `<span class="sw" style="background:${s.glow1}"></span>${s.name}`;
      b.setAttribute("aria-pressed", String(k === "aurora"));
      b.addEventListener("click", () => {
        meet.nova.o.skin = k;
        $$(".chip", skinsEl).forEach(x => x.setAttribute("aria-pressed", String(x === b)));
      });
      skinsEl.append(b);
    }
  }
  const danceBtn = $('[data-act="dance"]');
  function stopDance() {
    if (!dancing) return;
    dancing = false;
    Nova2.Music.stop();
    danceBtn?.setAttribute("aria-pressed", "false");
  }
  $$("[data-act]").forEach(b => b.addEventListener("click", () => {
    if (!meet) return;
    const act = b.dataset.act;
    if (act === "dance") {
      if (dancing) { stopDance(); return; }
      Nova2.Snd.enable(true);
      Nova2.Music.demo();
      dancing = true;
      b.setAttribute("aria-pressed", "true");
      return;
    }
    meet.nova.play(act, true);
  }));

  // ---------- Hey Nova phrases ----------
  const REPLIES = {
    status: "Claude Code is working: running swift test. Gemini CLI needs your approval.",
    deny: "Denied. Gemini CLI won't run that.",
    scan: "Your security score is 84. To fix: stealth mode. Open Nova Guard for one-click fixes.",
    music: "Playing Kaathalae Kaathalae.",
    dance: "Let's dance! 🎶",
    joke: "Why do programmers prefer dark mode? Because light attracts bugs.",
    allow: "For your safety I can only deny by voice. Please approve it on screen.",
    search: "Searching for swift concurrency.",
    whatsapp: "To Amma: I'll be late. Say send, or cancel.",
    check: "Security score 84. I found 2 things to look at: Firewall stealth mode, and Screen lock password. The rest are in Nova Guard.",
  };
  const replyEl = $("[data-voice-reply]");
  $$("[data-say]").forEach(b => b.addEventListener("click", () => {
    $$("[data-say]").forEach(x => x.setAttribute("aria-pressed", String(x === b)));
    const key = b.dataset.say;
    if (replyEl) {
      replyEl.textContent = "…";
      setTimeout(() => { replyEl.textContent = REPLIES[key]; }, reduceMotion ? 0 : 450);
    }
    play(key === "allow" || key === "deny" ? "error" : "listening");
    if (key === "dance" && meet) {
      meet.nova.play("spinHop", true);
      meet.nova.setMood("happy");
    }
  }));

  // ---------- Download: Nova waves ----------
  const wave = addLive($("[data-download-nova]"), { viewBox: "-20 -24 280 268" });
  wave?.nova.setMood("notification");

  // ---------- One loop for everything visible ----------
  [...lives, ...scenes].forEach(x => io.observe(x.el));
  let last = performance.now();
  function loop(now) {
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    if (!document.hidden) {
      for (const x of lives) if (x.visible) x.nova.frame(dt, x.music());
      for (const x of scenes) {
        if (!x.visible) continue;
        x.scenes.set(x.name());
        const music = x === meetWall && dancing ? Nova2.Music.update() : null;
        x.scenes.frame(reduceMotion ? 0 : now / 1000, reduceMotion ? 0 : dt,
          { beat: music ? music.beat : (x === heroWall && heroShot === "dance" ? now / 500 : 0), spec: music ? music.spec : null, tint: "#53E7FF" });
      }
    }
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);

  // ---------- Guard ring: counts up once when it scrolls into view ----------
  const ring = $(".ring");
  if (ring) {
    const value = $(".value", ring), label = $(".score", ring);
    const fillTo = (target, from = 0) => {
      value.style.strokeDashoffset = String(314 * (1 - target / 100));
      if (reduceMotion) { label.textContent = target; return; }
      const start = performance.now();
      (function tick(now) {
        const k = Math.min((now - start) / 1200, 1);
        label.textContent = Math.round(from + (target - from) * (1 - (1 - k) ** 3));
        if (k < 1) requestAnimationFrame(tick);
      })(start);
    };
    new IntersectionObserver(([e], obs) => { if (e.isIntersecting) { fillTo(Number(label.dataset.target)); obs.disconnect(); } }, { threshold: 0.5 }).observe(ring);
    $(".checks button", ring.parentElement)?.addEventListener("click", e => {
      const li = e.target.closest("li");
      li.className = "ok";
      li.firstChild.textContent = "Stealth mode ";
      e.target.remove();
      play("success");
      fillTo(100, Number(label.textContent));
    });
  }
})();
