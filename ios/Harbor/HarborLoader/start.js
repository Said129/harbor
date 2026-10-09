window.harborLoader = window.lottie.loadAnimation({
  container: document.getElementById("boat"),
  renderer: "svg",
  loop: true,
  autoplay: false,
  animationData: window.harborAnimation,
});

// The native display link supplies elapsed time. WebKit can suspend a page's
// animation callbacks while this small, noninteractive view remains visible.
(function () {
  var animation = window.harborLoader;
  var running = false;
  var frameRate = Number(window.harborAnimation.fr) || 30;
  window.harborLoaderMotion = {
    play: function () {
      running = true;
    },
    render: function (seconds) {
      if (!running || !animation.isLoaded || animation.totalFrames <= 0) return;
      animation.goToAndStop((seconds * frameRate) % animation.totalFrames, true);
    },
    stop: function () {
      running = false;
      animation.goToAndStop(0, true);
    },
    destroy: function () {
      this.stop();
      animation.destroy();
    },
  };
})();
