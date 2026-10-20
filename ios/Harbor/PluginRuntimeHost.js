(function () {
  "use strict";

  // Trusted, pinned programs are injected by the native host. Installed code runs only in the worker.
  globalThis.installHarborPluginHost = function (sandbox, parseHtml, compose, instance) {
    let worker = null;
    let sourceURL = null;
    const encoder = new TextEncoder();
    const maximum = 8 * 1024 * 1024;
    function post(message) {
      const value = JSON.stringify({ ...message, instance });
      if (encoder.encode(value).byteLength > maximum) throw new Error("plugin message too large");
      globalThis.webkit.messageHandlers.harborPlugin.postMessage(value);
    }
    function bridge(id, ok, value, error) {
      worker?.postMessage({ type: "bridgeResult", id, ok, value, error });
    }
    function dispose() {
      worker?.terminate();
      worker = null;
      if (sourceURL) URL.revokeObjectURL(sourceURL);
      sourceURL = null;
    }
    const api = {
      initialize(payload) {
        if (worker) throw new Error("plugin already initialized");
        const source =
          payload.format === "provider-script"
            ? compose.provider(payload.source, payload.meta)
            : payload.format === "harbor"
              ? compose.harbor(payload.source)
              : payload.source;
        sourceURL = URL.createObjectURL(new Blob([sandbox], { type: "text/javascript" }));
        worker = new Worker(sourceURL);
        worker.onmessage = function (event) {
          const message = event.data;
          if (!message || typeof message !== "object") return;
          try {
            if (message.type === "parse") {
              const html = String(message.payload?.html ?? "");
              if (encoder.encode(html).byteLength > 6 * 1024 * 1024)
                throw new Error("plugin HTML too large");
              bridge(message.id, true, parseHtml(html));
            } else if (
              [
                "http",
                "grpc",
                "ready",
                "initError",
                "result",
                "error",
                "cancelled",
                "log",
                "pong",
              ].includes(message.type)
            ) {
              post(message);
            }
          } catch (error) {
            if (message.type === "parse")
              bridge(message.id, false, undefined, String(error.message));
            else if (message.id)
              post({ type: "error", id: message.id, error: String(error.message) });
            else post({ type: "fatal", error: "plugin bridge failed" });
          }
        };
        worker.onerror = () => post({ type: "fatal", error: "plugin worker failed" });
        worker.onmessageerror = () => post({ type: "fatal", error: "plugin message clone failed" });
        worker.postMessage({ type: "init", source, config: payload.configuration ?? {} });
      },
      call(message) {
        if (!worker) throw new Error("plugin worker unavailable");
        worker.postMessage({
          type: "call",
          id: message.id,
          method: message.method,
          args: message.args,
        });
      },
      cancel(id) {
        worker?.postMessage({ type: "cancel", id });
      },
      bridgeResult(message) {
        bridge(message.id, message.ok, message.value, message.error);
      },
      dispose,
    };
    globalThis.harborPluginHost = Object.freeze(api);
    post({ type: "hostReady" });
  };
})();
