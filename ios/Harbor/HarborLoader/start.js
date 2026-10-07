window.harborLoader = window.lottie.loadAnimation({
  container: document.getElementById("boat"),
  renderer: "svg",
  loop: true,
  autoplay: false,
  animationData: window.harborAnimation,
});

// Use the page clock while Lottie renders its original SVG. Its goToAndStop
// method pauses Lottie's own clock; native motion controls remain separate.
(function () {
  var animation = window.harborLoader;
  var started = performance.now();
  var running = false;
  var frameRate = Number(window.harborAnimation.fr) || 30;
  var lastFrame = 0;
  var request = null;
  function tick(now) {
    request = null;
    if (!running) return;
    if (animation.isLoaded && animation.totalFrames > 0) {
      lastFrame = (((now - started) / 1000) * frameRate) % animation.totalFrames;
      animation.goToAndStop(lastFrame, true);
    }
    request = window.requestAnimationFrame(tick);
  }
  window.harborLoaderMotion = {
    play: function () {
      if (running) return;
      running = true;
      started = performance.now() - (lastFrame / frameRate) * 1000;
      request = window.requestAnimationFrame(tick);
    },
    stop: function () {
      running = false;
      if (request !== null) window.cancelAnimationFrame(request);
      request = null;
      lastFrame = 0;
      animation.goToAndStop(0, true);
    },
    destroy: function () {
      this.stop();
      animation.destroy();
    },
  };
  window.harborLoaderMotion.play();
})();
