(function () {
  "use strict";

  // Trusted, pinned programs are injected by the native host. Installed code runs only in the worker.
  globalThis.installHarborPluginHost = function (
    sandbox,
    parseHtml,
    compose,
    instance,
    createHTML,
  ) {
    let worker = null;
    let trustedHTML = null;
    let closed = false;
    let htmlSequence = 0;
    const htmlBridges = new Map();
    const htmlCalls = new Set();
    let sourceURL = null;
    const jsonCalls = new Set();
    const encoder = new TextEncoder();
    const maximum = 64 * 1024 * 1024;
    function post(message) {
      const value = JSON.stringify({ ...message, instance });
      if (encoder.encode(value).byteLength > maximum) throw new Error("plugin message too large");
      globalThis.webkit.messageHandlers.harborPlugin.postMessage(value);
    }
    function bridge(id, ok, value, error) {
      const html = htmlBridges.get(id);
      if (html) {
        htmlBridges.delete(id);
        if (ok) html.resolve(value);
        else html.reject(new Error(String(error || "HTML source request failed")));
        return;
      }
      worker?.postMessage({ type: "bridgeResult", id, ok, value, error });
    }
    function dispose() {
      closed = true;
      htmlCalls.clear();
      for (const pending of htmlBridges.values()) pending.reject(new Error("HTML source disposed"));
      htmlBridges.clear();
      trustedHTML = null;
      jsonCalls.clear();
      worker?.terminate();
      worker = null;
      if (sourceURL) URL.revokeObjectURL(sourceURL);
      sourceURL = null;
    }
    const api = {
      initialize(payload) {
        if (worker || trustedHTML) throw new Error("plugin already initialized");
        if (payload.format === "trusted-html") {
          try {
            if (typeof createHTML !== "function")
              throw new Error("HTML source program unavailable");
            trustedHTML = createHTML(
              payload,
              (payload) =>
                new Promise((resolve, reject) => {
                  if (closed) {
                    reject(new Error("HTML source disposed"));
                    return;
                  }
                  const id = "html-http-" + ++htmlSequence;
                  htmlBridges.set(id, { resolve, reject });
                  post({ type: "http", id, payload });
                }),
            );
            Promise.resolve(trustedHTML.prepare?.())
              .then(() => {
                if (!closed) post({ type: "ready", meta: trustedHTML.meta });
              })
              .catch((error) => {
                if (!closed) post({ type: "initError", error: String(error.message) });
              });
          } catch (error) {
            post({ type: "initError", error: String(error.message) });
          }
          return;
        }
        const source =
          payload.format === "provider-script"
            ? compose.provider(payload.source, payload.meta)
            : payload.format === "harbor"
              ? compose.harbor(payload.source)
              : payload.source;
        sourceURL = URL.createObjectURL(new Blob([sandbox], { type: "text/javascript" }));
        worker = new Worker(sourceURL);
        worker.onmessage = function (event) {
          let message = event.data;
          if (!message || typeof message !== "object") return;
          try {
            if (["result", "error", "cancelled"].includes(message.type)) {
              const jsonResult = jsonCalls.delete(message.id);
              if (jsonResult && message.type === "result")
                message = { ...message, value: JSON.stringify(message.value) ?? "null" };
            }
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
        if (trustedHTML) {
          htmlCalls.add(message.id);
          Promise.resolve()
            .then(() => trustedHTML.call(message.method, message.args ?? []))
            .then((value) => {
              if (!htmlCalls.delete(message.id) || closed) return;
              post({
                type: "result",
                id: message.id,
                value: message.jsonResult === true ? (JSON.stringify(value) ?? "null") : value,
              });
            })
            .catch((error) => {
              if (htmlCalls.delete(message.id) && !closed)
                post({ type: "error", id: message.id, error: String(error.message) });
            });
          return;
        }
        if (!worker) throw new Error("plugin worker unavailable");
        if (message.jsonResult === true) jsonCalls.add(message.id);
        worker.postMessage({
          type: "call",
          id: message.id,
          method: message.method,
          args: message.args,
        });
      },
      cancel(id) {
        if (htmlCalls.delete(id)) post({ type: "cancelled", id });
        jsonCalls.delete(id);
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
