// Interactive dummy of the Mandoline app. No files are touched — it's a
// front-end recreation using the TestMedia images.
(function () {
  "use strict";

  var FILES = [
    { name: "image_4.jpg", bytes: 65534 },
    { name: "image_5.jpg", bytes: 90210 },
    { name: "image_6.jpg", bytes: 41431 },
    { name: "image_7.jpg", bytes: 83381 },
    { name: "image_8.jpg", bytes: 39549 },
    { name: "image_9.jpg", bytes: 51788 },
    { name: "image_10.jpg", bytes: 55762 }
  ];

  var demo = document.getElementById("demo");
  if (!demo) return;

  var el = {
    idx: document.getElementById("demo-idx"),
    count: document.getElementById("demo-count"),
    fname: document.getElementById("demo-fname"),
    fsize: document.getElementById("demo-fsize"),
    ftotal: document.getElementById("demo-ftotal"),
    media: document.getElementById("demo-media"),
    flash: document.getElementById("demo-flash"),
    empty: document.getElementById("demo-empty"),
    reset: document.getElementById("demo-reset"),
    carousel: document.getElementById("demo-carousel")
  };

  var queue = [];   // remaining items
  var sel = 0;      // selected index into queue
  var history = []; // { item, index } for undo

  function fmt(bytes) {
    if (bytes >= 1e6) return (bytes / 1e6).toFixed(1) + " MB";
    return Math.round(bytes / 1024) + " KB";
  }
  function total() {
    return queue.reduce(function (s, f) { return s + f.bytes; }, 0);
  }

  function buildCarousel() {
    el.carousel.innerHTML = "";
    queue.forEach(function (f, i) {
      var t = document.createElement("button");
      t.className = "demo-thumb" + (i === sel ? " is-active" : "");
      t.style.backgroundImage = 'url("demo/' + f.name + '")';
      t.setAttribute("aria-label", f.name);
      t.addEventListener("click", function () {
        sel = i;
        demo.focus();
        render();
      });
      el.carousel.appendChild(t);
    });
  }

  function render() {
    var empty = queue.length === 0;
    el.empty.hidden = !empty;
    el.media.style.visibility = empty ? "hidden" : "visible";

    if (!empty) {
      if (sel >= queue.length) sel = queue.length - 1;
      var f = queue[sel];
      el.media.src = "demo/" + f.name;
      el.fname.textContent = f.name;
      el.fsize.textContent = fmt(f.bytes);
      el.idx.textContent = String(sel + 1);
    } else {
      el.idx.textContent = "0";
    }
    el.count.textContent = String(queue.length);
    el.ftotal.textContent = fmt(total());
    buildCarousel();
    scrollSelIntoView();
  }

  function scrollSelIntoView() {
    var active = el.carousel.querySelector(".is-active");
    if (active && active.scrollIntoView) {
      active.scrollIntoView({ inline: "center", block: "nearest", behavior: "smooth" });
    }
  }

  var flashTimer = null;
  function flash(color) {
    // Snap to the color, then fade it out — a brief camera-like flash, like the app.
    el.flash.style.transition = "none";
    el.flash.style.background = color;
    el.flash.style.opacity = "0.42";
    void el.flash.offsetWidth; // force reflow so the next change animates
    el.flash.style.transition = "opacity 320ms ease-out";
    el.flash.style.opacity = "0";
  }

  function removeCurrent(color) {
    if (queue.length === 0) return;
    var removed = queue[sel];
    history.push({ item: removed, index: sel });
    flash(color);
    queue.splice(sel, 1);
    if (sel >= queue.length) sel = Math.max(0, queue.length - 1);
    render();
  }

  function trash() { removeCurrent("#e57373"); } // app danger red
  function keep() { removeCurrent("#4caf50"); }  // app success green

  function undo() {
    if (history.length === 0) return;
    var last = history.pop();
    var at = Math.min(last.index, queue.length);
    queue.splice(at, 0, last.item);
    sel = at;
    flash("#c9ccd2"); // neutral grey, like the app's undo flash
    render();
  }

  function prev() { if (sel > 0) { sel--; render(); } }
  function next() { if (sel < queue.length - 1) { sel++; render(); } }

  function start() {
    queue = FILES.map(function (f) { return { name: f.name, bytes: f.bytes }; });
    sel = 0;
    history = [];
    render();
  }

  demo.addEventListener("click", function () { demo.focus(); });
  el.reset.addEventListener("click", function (e) {
    e.stopPropagation();
    start();
    demo.focus();
  });

  demo.addEventListener("keydown", function (e) {
    var handled = true;
    switch (e.key) {
      case "ArrowLeft": prev(); break;
      case "ArrowRight": next(); break;
      case "]": keep(); break;
      case "[": trash(); break;
      case "z": case "Z": undo(); break;
      default: handled = false;
    }
    if (handled) e.preventDefault();
  });

  start();
})();
