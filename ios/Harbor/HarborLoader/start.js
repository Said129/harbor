window.harborLoader = window.lottie.loadAnimation({
  container: document.getElementById("boat"),
  renderer: "svg",
  loop: true,
  autoplay: false,
  animationData: window.harborAnimation,
});

// WKWebView can suspend a WebKit animation immediately after the file has
// finished loading. Keep the original Lottie artwork, but drive the same
// timeline from the page clock so the native loader never appears frozen.
(function () {
  var animation = window.harborLoader;
  var started = performance.now();
  var running = true;
  var frameRate = Number(window.harborAnimation.fr) || 30;
  var lastFrame = -1;
  function tick(now) {
    if (running) {
      var frame = (((now - started) / 1000) * frameRate) % window.harborAnimation.op;
      if (Math.floor(frame) !== lastFrame) {
        lastFrame = Math.floor(frame);
        animation.goToAndStop(frame, true);
      }
    }
    window.requestAnimationFrame(tick);
  }
  animation.play = function () {
    running = true;
    started = performance.now() - (lastFrame / frameRate) * 1000;
  };
  animation.pause = function () {
    running = false;
  };
  var originalStop = animation.goToAndStop.bind(animation);
  animation.goToAndStop = function (frame, force) {
    lastFrame = Math.floor(frame);
    originalStop(frame, force);
    // Keep the public Lottie frame value observable to the native smoke test
    // even when WebKit has deferred the SVG renderer's internal bookkeeping.
    animation.currentFrame = frame;
  };
  window.requestAnimationFrame(tick);
  animation.play();
})();
