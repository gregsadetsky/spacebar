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
  // matroska codec ids sit in the first few KB as plain ascii; one range
  // request on the host's stream url tells us what we're refusing
  var NAMES = { "V_AV1": "AV1", "V_VP9": "VP9", "V_VP8": "VP8", "V_MPEG4/ISO/AVC": "H.264", "V_MPEGH/ISO/HEVC": "HEVC", "V_THEORA": "Theora",
                "A_OPUS": "Opus", "A_VORBIS": "Vorbis", "A_AAC": "AAC", "A_FLAC": "FLAC", "A_MPEG/L3": "MP3", "A_AC3": "AC-3", "A_EAC3": "E-AC-3" };
  function codecs() {
    return fetch(sb.data, { headers: { Range: "bytes=0-65535" } }).then(function (r) { return r.arrayBuffer(); }).then(function (buf) {
      var text = "", bytes = new Uint8Array(buf);
      for (var i = 0; i < bytes.length; i++) text += bytes[i] >= 32 && bytes[i] < 127 ? String.fromCharCode(bytes[i]) : " ";
      var found = [];
      Object.keys(NAMES).forEach(function (id) { if (text.indexOf(id) >= 0) found.push(NAMES[id]); });
      return found;
    }).catch(function () { return []; });
  }
  v.addEventListener("error", function () {
    var e = v.error;
    if (e && e.code === 4) {
      codecs().then(function (found) {
        var video = found.filter(function (c) { return ["AV1", "VP9", "VP8", "H.264", "HEVC", "Theora"].indexOf(c) >= 0; });
        var why;
        if (video.indexOf("AV1") >= 0) why = "this WebM is AV1, which macOS's WebKit can't decode. VP9 or VP8 would play; with yt-dlp: -S vcodec:vp9";
        else if (found.length) why = "WebKit can't decode this WebM (" + found.join(" + ") + "); VP8/VP9 video with Opus/Vorbis audio works";
        else why = "WebKit can't decode this file; WebM needs VP8/VP9 video with Opus/Vorbis audio";
        finish(false, why);
      });
      return;
    }
    var why = !e ? "unknown error" : e.code === 3 ? "decoding failed partway through" : e.code === 2 ? "the file could not be read" : "playback aborted";
    finish(false, why + (e && e.message ? " (" + e.message + ")" : ""));
  });
  // a file that never produces metadata and never errors would hit the host's 3 s timeout; fine
  v.src = sb.data;
})();
