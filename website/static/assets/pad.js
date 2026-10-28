/* "Try a stroke" pad: draw with the left or right button (or a finger) and the
   stroke is matched against StrokeMouse's seven built-in gestures.
   The app itself uses elastic whole-path matching; this demo only needs the
   direction sequence of each stroke (e.g. down then left). */
(function () {
  'use strict';

  var pad = document.querySelector('[data-pad]');
  if (!pad) return;
  var surface = pad.querySelector('[data-pad-surface]');
  var canvas = pad.querySelector('[data-pad-canvas]');
  var status = pad.querySelector('[data-pad-status]');
  var result = pad.querySelector('[data-pad-result]');
  var resultPath = pad.querySelector('[data-pad-result-path]');
  var resultName = pad.querySelector('[data-pad-result-name]');
  var resultAction = pad.querySelector('[data-pad-result-action]');
  var gestures = JSON.parse(pad.dataset.gestures);
  var text = JSON.parse(pad.dataset.text);
  var glyphs = Array.prototype.slice.call(pad.querySelectorAll('[data-gesture]'));
  var ctx = canvas.getContext('2d');
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  var points = [];
  var drawing = false;
  var pointerId = null;
  var fadeTimer = null;
  var playToken = 0;
  var width = 0;
  var height = 0;

  function cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  function resize() {
    var rect = surface.getBoundingClientRect();
    var ratio = window.devicePixelRatio || 1;
    width = rect.width;
    height = rect.height;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    paint(1);
  }

  function paint(alpha) {
    ctx.clearRect(0, 0, width, height);
    if (points.length < 2) return;
    ctx.globalAlpha = alpha;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = cssVar('--accent');
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    // Midpoint quadratic smoothing keeps fast strokes from looking jagged.
    for (var i = 1; i < points.length - 1; i++) {
      var mx = (points[i].x + points[i + 1].x) / 2;
      var my = (points[i].y + points[i + 1].y) / 2;
      ctx.quadraticCurveTo(points[i].x, points[i].y, mx, my);
    }
    var last = points[points.length - 1];
    ctx.lineTo(last.x, last.y);
    ctx.stroke();
    ctx.fillStyle = cssVar('--start');
    ctx.beginPath();
    ctx.arc(points[0].x, points[0].y, 5.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  function setStatus(message, ok) {
    status.textContent = message;
    status.classList.toggle('is-ok', !!ok);
  }

  /* -------------------------------------------------------------- recognition */

  function pathLength(pts) {
    var total = 0;
    for (var i = 1; i < pts.length; i++) total += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
    return total;
  }

  function directions(pts) {
    var total = pathLength(pts);
    var step = Math.max(6, total / 48);
    var runs = [];
    var anchor = pts[0];
    for (var i = 1; i < pts.length; i++) {
      var dx = pts[i].x - anchor.x;
      var dy = pts[i].y - anchor.y;
      var dist = Math.hypot(dx, dy);
      if (dist < step) continue;
      var dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'R' : 'L') : (dy > 0 ? 'D' : 'U');
      var run = runs[runs.length - 1];
      if (run && run.dir === dir) run.len += dist; else runs.push({ dir: dir, len: dist });
      anchor = pts[i];
    }
    // Drop jitter shorter than 15% of the stroke, then merge neighbours.
    var kept = [];
    runs.forEach(function (r) {
      if (r.len < total * 0.15) return;
      var prev = kept[kept.length - 1];
      if (prev && prev.dir === r.dir) prev.len += r.len; else kept.push({ dir: r.dir, len: r.len });
    });
    return kept.map(function (r) { return r.dir; }).join('');
  }

  function recognize() {
    if (pathLength(points) < 36) return { short: true };
    var seq = directions(points);
    for (var i = 0; i < gestures.length; i++) {
      if (gestures[i].seq === seq) return { gesture: gestures[i] };
    }
    return { miss: true };
  }

  function actionHTML(action) {
    var div = document.createElement('div');
    div.textContent = action;
    return div.innerHTML.replace(/\{([^{}]+)\}/g, '<kbd>$1</kbd>');
  }

  function showResult(outcome) {
    glyphs.forEach(function (g) { g.classList.toggle('is-active', !!outcome.gesture && g.dataset.gesture === outcome.gesture.key); });
    if (outcome.gesture) {
      var g = outcome.gesture;
      resultPath.setAttribute('d', g.d);
      resultName.textContent = g.name;
      resultAction.innerHTML = actionHTML(g.action);
      result.classList.remove('is-miss');
      result.hidden = false;
      setStatus(text.matched + ' · ' + g.seq.split('').map(function (c) { return { U: '↑', D: '↓', L: '←', R: '→' }[c]; }).join(''), true);
    } else {
      result.hidden = true;
      setStatus(outcome.short ? text.short : text.nomatch);
    }
    clearTimeout(fadeTimer);
    fadeTimer = setTimeout(fadeOut, 2600);
  }

  function fadeOut() {
    if (drawing) return;
    var start = performance.now();
    var tick = function (now) {
      var t = Math.min(1, (now - start) / 500);
      paint(1 - t);
      if (t < 1 && !drawing) requestAnimationFrame(tick);
      else if (!drawing) { points = []; result.hidden = true; surface.classList.remove('is-active'); setStatus(text.idle); }
    };
    requestAnimationFrame(tick);
  }

  /* -------------------------------------------------------------- input */

  function local(event) {
    var rect = surface.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  surface.addEventListener('contextmenu', function (event) { event.preventDefault(); });
  surface.addEventListener('pointerdown', function (event) {
    if (event.button !== 0 && event.button !== 2) return;
    event.preventDefault();
    playToken++;
    clearTimeout(fadeTimer);
    drawing = true;
    pointerId = event.pointerId;
    try { surface.setPointerCapture(pointerId); } catch (e) { /* synthetic or already-released pointer */ }
    surface.classList.add('is-active');
    result.hidden = true;
    points = [local(event)];
    setStatus(text.drawing);
    paint(1);
  });
  surface.addEventListener('pointermove', function (event) {
    if (!drawing || event.pointerId !== pointerId) return;
    var events = event.getCoalescedEvents ? event.getCoalescedEvents() : [];
    if (!events.length) events = [event];
    events.forEach(function (e) { points.push(local(e)); });
    paint(1);
  });
  function finish(event) {
    if (!drawing || event.pointerId !== pointerId) return;
    drawing = false;
    points.push(local(event));
    paint(1);
    showResult(recognize());
  }
  surface.addEventListener('pointerup', finish);
  surface.addEventListener('pointercancel', function (event) {
    if (event.pointerId !== pointerId) return;
    drawing = false;
    fadeOut();
  });

  /* -------------------------------------------------------------- demo playback */

  function samplePath(d) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    svg.setAttribute('d', d);
    var total = svg.getTotalLength();
    var size = Math.min(width, height) * 0.62;
    var ox = (width - size) / 2;
    var oy = (height - size) / 2;
    var out = [];
    for (var i = 0; i <= 60; i++) {
      var p = svg.getPointAtLength((total * i) / 60);
      out.push({ x: ox + (p.x / 100) * size, y: oy + (p.y / 100) * size });
    }
    return out;
  }

  glyphs.forEach(function (button) {
    button.addEventListener('click', function () {
      var gesture = gestures.filter(function (g) { return g.key === button.dataset.gesture; })[0];
      if (!gesture || drawing) return;
      var token = ++playToken;
      var path = samplePath(gesture.d);
      clearTimeout(fadeTimer);
      result.hidden = true;
      surface.classList.add('is-active');
      setStatus(text.drawing);
      var start = performance.now();
      var duration = reduceMotion ? 1 : 750;
      var tick = function (now) {
        if (token !== playToken) return;
        var t = Math.min(1, (now - start) / duration);
        var eased = 1 - Math.pow(1 - t, 3);
        points = path.slice(0, Math.max(2, Math.round(eased * path.length)));
        paint(1);
        if (t < 1) requestAnimationFrame(tick);
        else showResult({ gesture: gesture });
      };
      requestAnimationFrame(tick);
    });
  });

  // Repaint in the new accent color when the theme flips.
  new MutationObserver(function () { paint(1); }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  if ('ResizeObserver' in window) new ResizeObserver(resize).observe(surface); else window.addEventListener('resize', resize);
  resize();
})();
