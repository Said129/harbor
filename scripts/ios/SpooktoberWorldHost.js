import { mountSpooktober } from "./spooktober/native-entry.js";

const scroller = document.getElementById("world");
const root = scroller.attachShadow({ mode: "open" });
let runtime = null,
  active = true;
let appearance = window.__harborSpookAppearance;
let musicState = window.__harborSpookMusicState;
let loadingGlyph = "";
let playingCard = null,
  playingMark = null,
  playingPhase = null;
const musicObserver = new MutationObserver(syncMusicMark);
const post = (value) => window.webkit.messageHandlers.spooktober.postMessage(JSON.stringify(value));
function applyAppearance(value) {
  if (!value) return;
  const previous = appearance?.css ?? {};
  appearance = value;
  document.documentElement.lang = value.language;
  document.documentElement.dir = value.direction;
  for (const key of Object.keys(previous))
    if (!(key in value.css)) document.documentElement.style.removeProperty(key);
  for (const [key, color] of Object.entries(value.css))
    document.documentElement.style.setProperty(key, color);
  scroller.dataset.showImdb = String(value.showIMDb);
  scroller.style.background = "var(--color-canvas)";
  document.body.style.background = "var(--color-canvas)";
  if (playingMark)
    playingMark
      .querySelector(".music-live-mark")
      .setAttribute(
        "aria-label",
        value.labels[playingPhase === "resolving" ? "music.loading" : "music.nowPlaying"],
      );
}
function clearMusicMark() {
  playingCard?.removeAttribute("aria-current");
  playingMark?.remove();
  playingCard = playingMark = playingPhase = null;
}
function syncMusicMark() {
  const id =
    musicState?.originKind === "playlist" && musicState.originId?.startsWith("spooktober:")
      ? musicState.originId.slice(11)
      : null;
  const visible =
    active &&
    Boolean(musicState?.trackId) &&
    ["playing", "paused", "resolving"].includes(musicState.phase);
  const next =
    visible && id
      ? Array.from(root.querySelectorAll(".playlist-card")).find(
          (card) => card.dataset.playlist === id,
        )
      : null;
  const target = next?.querySelector(".mix-art");
  if (!target) {
    clearMusicMark();
    return;
  }
  if (
    playingCard === next &&
    playingMark?.parentElement === target &&
    playingPhase === musicState.phase
  )
    return;
  clearMusicMark();
  playingCard = next;
  playingPhase = musicState.phase;
  next.setAttribute("aria-current", "true");
  playingMark = document.createElement("span");
  playingMark.className = "spook-playlist-playing";
  if (playingPhase === "paused") playingMark.dataset.paused = "true";
  const mark = document.createElement("span");
  mark.className = "music-live-mark";
  mark.setAttribute("role", "img");
  mark.setAttribute(
    "aria-label",
    appearance.labels[playingPhase === "resolving" ? "music.loading" : "music.nowPlaying"],
  );
  if (playingPhase === "resolving") {
    mark.dataset.loading = "true";
    mark.innerHTML = loadingGlyph;
  } else {
    const bars = document.createElement("span");
    bars.className = "music-eq-bars";
    bars.setAttribute("aria-hidden", "true");
    for (let i = 0; i < 4; i++) bars.append(document.createElement("i"));
    mark.append(bars);
  }
  playingMark.append(mark);
  target.append(playingMark);
}
function setMusicState(value) {
  musicObserver.disconnect();
  musicState = value;
  syncMusicMark();
  if (
    active &&
    value?.trackId &&
    value.originKind === "playlist" &&
    value.originId?.startsWith("spooktober:") &&
    ["playing", "paused", "resolving"].includes(value.phase)
  )
    musicObserver.observe(root, { childList: true, subtree: true });
}
applyAppearance(appearance);
window.__harborSpookWorld = {
  setAppearance: applyAppearance,
  setMusicState,
  setActive(value) {
    active = Boolean(value);
    runtime?.setActive(active);
    setMusicState(musicState);
  },
  back() {
    return runtime?.back() ?? false;
  },
  forget() {
    runtime?.forget();
  },
  dispose() {
    musicObserver.disconnect();
    clearMusicMark();
    runtime?.dispose();
    runtime = null;
  },
};
try {
  runtime = await mountSpooktober({
    root,
    scroller,
    onIntent: (message) => post({ kind: "intent", message }),
  });
  const sheets = await Promise.all(
    ["music-now-playing-mark.css", "harbor-theme.css"].map(async (file) => {
      const response = await fetch("./spooktober/" + file);
      if (!response.ok) throw new Error("Spooktober Harbor styles unavailable");
      return response.text();
    }),
  );
  const nativeTheme = document.createElement("style");
  nativeTheme.dataset.harborTheme = "";
  nativeTheme.textContent = sheets.join("\n");
  root.append(nativeTheme);
  const glyph = await fetch("./spooktober/music-loading.svg");
  if (!glyph.ok) throw new Error("Spooktober music mark unavailable");
  const raw = await glyph.text();
  const paths = raw
    .slice(raw.indexOf(">", raw.indexOf("<svg")) + 1, raw.lastIndexOf("</svg>"))
    .replace(/\sid="[^"]*"/g, "")
    .replace(/(fill|stroke)="#[0-9a-fA-F]{3,8}"/g, '$1="currentColor"');
  loadingGlyph =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="13" height="13" aria-hidden="true" focusable="false" class="animate-spin motion-reduce:animate-none" style="flex-shrink:0">' +
    paths +
    "</svg>";
  applyAppearance(appearance);
  runtime.setActive(active);
  setMusicState(musicState);
  document.documentElement.dataset.spooktoberReady = "true";
  post({ kind: "ready" });
} catch (error) {
  post({ kind: "failed", message: String(error).slice(0, 512) });
}
