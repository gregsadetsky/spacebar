// video plugin: the host streams the file at spacebar.data (spacebar-file:///current)
// with range support, so this is just a <video>. webkit decides what decodes:
// webm with vp8/vp9 + opus/vorbis works on macos 15; mkv and av1 do not.
(function () {
  "use strict";
  var sb = window.spacebar;
  var v = document.getElementById("v");
  var finished = false;
  function finish(ok, message) {
    if (finished) return;
    finished = true;
    if (ok) sb.done(); else sb.fail(message);
  }
  function fmt(t) {
    if (!isFinite(t)) return "live";
    var m = Math.floor(t / 60), s = Math.floor(t % 60);
    return m + ":" + (s < 10 ? "0" : "") + s;
  }
  v.addEventListener("loadedmetadata", function () {
    document.getElementById("dims").textContent = v.videoWidth + "×" + v.videoHeight;
    document.getElementById("dur").textContent = fmt(v.duration);
    sb.log("metadata " + v.videoWidth + "x" + v.videoHeight + " " + v.duration.toFixed(2) + "s");
    finish(true);
  });
  // proof that frames actually decode (smoke greps for this line)
  var reported = false;
  v.addEventListener("timeupdate", function () {
    if (!reported && v.currentTime > 0.3) { reported = true; sb.log("playing t=" + v.currentTime.toFixed(2)); }
  });
  v.addEventListener("error", function () {
    var e = v.error;
    var why = !e ? "unknown error" :
      e.code === 4 ? "this file's format or codec is not supported by WebKit (WebM needs VP8/VP9 + Opus/Vorbis)" :
      e.code === 3 ? "decoding failed partway through" :
      e.code === 2 ? "the file could not be read" : "playback aborted";
    finish(false, why + (e && e.message ? " (" + e.message + ")" : ""));
  });
  // a file that never produces metadata and never errors would hit the host's 3 s timeout; fine
  v.src = sb.data;
})();
