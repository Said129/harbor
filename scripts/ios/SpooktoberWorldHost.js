import { mountSpooktober } from "./spooktober/native-entry.js";

const scroller = document.getElementById("world");
const root = scroller.attachShadow({ mode: "open" });
let runtime = null,
  active = true;
const post = (value) => window.webkit.messageHandlers.spooktober.postMessage(JSON.stringify(value));
window.__harborSpookWorld = {
  setActive(value) {
    active = Boolean(value);
    runtime?.setActive(active);
  },
  back() {
    return runtime?.back() ?? false;
  },
  forget() {
    runtime?.forget();
  },
  dispose() {
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
  runtime.setActive(active);
  document.documentElement.dataset.spooktoberReady = "true";
  post({ kind: "ready" });
} catch (error) {
  post({ kind: "failed", message: String(error).slice(0, 512) });
}
