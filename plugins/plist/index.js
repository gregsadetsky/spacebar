// everything the host gives you is on window.spacebar. call done() when rendered.
(function () {
  var sb = window.spacebar;
  try {
    document.getElementById("title").textContent = sb.file.name;
    document.getElementById("meta").textContent = sb.file.size + " bytes · " + sb.input + " · " + sb.theme;
    var data = sb.data;
    if (sb.input === "text") data = data.slice(0, 20000);
    else data = JSON.stringify(data, null, 2).slice(0, 20000);
    document.getElementById("out").textContent = data;
    sb.done();
  } catch (e) {
    sb.fail(String(e));
  }
})();
