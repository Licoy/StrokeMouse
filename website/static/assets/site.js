/* StrokeMouse site interactions. Pages are fully usable without this file. */
(function () {
  'use strict';

  var root = document.documentElement;
  root.classList.add('js');
  var $ = function (sel, ctx) { return (ctx || document).querySelector(sel); };
  var $$ = function (sel, ctx) { return Array.prototype.slice.call((ctx || document).querySelectorAll(sel)); };
  var store = {
    get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  };
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------------------------------------------------------------- theme */

  var media = window.matchMedia('(prefers-color-scheme: dark)');
  function applyTheme(pref) {
    var dark = pref === 'dark' || (pref === 'auto' && media.matches);
    root.dataset.theme = dark ? 'dark' : 'light';
    root.dataset.themePref = pref;
    $$('[data-theme-choice]').forEach(function (el) {
      el.setAttribute('aria-checked', String(el.dataset.themeChoice === pref));
    });
  }
  applyTheme(store.get('sm-theme') || 'auto');
  media.addEventListener('change', function () {
    if ((store.get('sm-theme') || 'auto') === 'auto') applyTheme('auto');
  });
  $$('[data-theme-choice]').forEach(function (el) {
    el.addEventListener('click', function () {
      store.set('sm-theme', el.dataset.themeChoice);
      applyTheme(el.dataset.themeChoice);
      closePopovers();
    });
  });

  /* ---------------------------------------------------------------- popovers */

  function closePopovers(except) {
    $$('[data-popover]').forEach(function (wrap) {
      if (wrap === except) return;
      var btn = $('[data-popover-toggle]', wrap);
      var menu = $('.popover', wrap);
      if (btn) btn.setAttribute('aria-expanded', 'false');
      if (menu) menu.hidden = true;
    });
  }
  $$('[data-popover]').forEach(function (wrap) {
    var btn = $('[data-popover-toggle]', wrap);
    var menu = $('.popover', wrap);
    btn.addEventListener('click', function (event) {
      event.stopPropagation();
      var open = btn.getAttribute('aria-expanded') !== 'true';
      closePopovers(wrap);
      btn.setAttribute('aria-expanded', String(open));
      menu.hidden = !open;
      if (open) { var first = $('a, button', menu); if (first) first.focus(); }
    });
    menu.addEventListener('keydown', function (event) {
      var items = $$('a, button', menu);
      var i = items.indexOf(document.activeElement);
      if (event.key === 'ArrowDown') { event.preventDefault(); items[(i + 1) % items.length].focus(); }
      if (event.key === 'ArrowUp') { event.preventDefault(); items[(i - 1 + items.length) % items.length].focus(); }
      if (event.key === 'Escape') { closePopovers(); btn.focus(); }
    });
  });
  document.addEventListener('click', function (event) {
    if (!event.target.closest('[data-popover]')) closePopovers();
  });

  // Choosing a language explicitly is remembered, so the root URL stops redirecting.
  $$('[data-locale-link]').forEach(function (a) {
    a.addEventListener('click', function () { store.set('sm-locale', a.dataset.localeLink); });
  });

  /* ---------------------------------------------------------------- header */

  var header = $('[data-header]');
  var onScroll = function () { header.classList.toggle('is-scrolled', window.scrollY > 4); };
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  var navToggle = $('[data-nav-toggle]');
  var mobileNav = $('[data-mobile-nav]');
  if (navToggle && mobileNav) {
    navToggle.addEventListener('click', function () {
      var open = navToggle.getAttribute('aria-expanded') !== 'true';
      navToggle.setAttribute('aria-expanded', String(open));
      mobileNav.hidden = !open;
    });
    window.matchMedia('(min-width: 861px)').addEventListener('change', function (m) {
      if (m.matches) { navToggle.setAttribute('aria-expanded', 'false'); mobileNav.hidden = true; }
    });
  }

  var isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
  if (!isMac) $$('[data-mod-key]').forEach(function (el) { el.textContent = 'Ctrl K'; });

  /* ---------------------------------------------------------------- reveal */

  var reveals = $$('.reveal');
  if ('IntersectionObserver' in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { entry.target.classList.add('is-visible'); io.unobserve(entry.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.06 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('is-visible'); });
  }

  /* ---------------------------------------------------------------- copy */

  function copyText(text, button) {
    var done = function () {
      button.classList.add('is-copied');
      var label = button.getAttribute('aria-label');
      if (button.dataset.copiedLabel) button.setAttribute('aria-label', button.dataset.copiedLabel);
      setTimeout(function () { button.classList.remove('is-copied'); button.setAttribute('aria-label', label); }, 1600);
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function () {});
    } else {
      var area = document.createElement('textarea');
      area.value = text; area.style.position = 'fixed'; area.style.opacity = '0';
      document.body.appendChild(area); area.select();
      try { document.execCommand('copy'); done(); } catch (e) {}
      area.remove();
    }
  }
  $$('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () { copyText(btn.dataset.copy, btn); });
  });
  var copyTemplate = $('.cmd-copy');
  $$('.prose .hl').forEach(function (block) {
    var pre = $('pre', block);
    if (!pre) return;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'code-copy';
    btn.setAttribute('aria-label', copyTemplate ? copyTemplate.getAttribute('aria-label') : 'Copy');
    btn.innerHTML = '<span class="cmd-copy-idle"><svg class="icon" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg></span><span class="cmd-copy-done"><svg class="icon" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg></span>';
    btn.addEventListener('click', function () { copyText(pre.innerText.replace(/\n$/, ''), btn); });
    block.appendChild(btn);
  });

  /* ---------------------------------------------------------------- tabs */

  function tabset(list, tabs, panels, onSelect) {
    function select(index, focus) {
      tabs.forEach(function (tab, i) {
        var on = i === index;
        tab.setAttribute('aria-selected', String(on));
        tab.tabIndex = on ? 0 : -1;
        panels[i].hidden = !on;
      });
      if (focus) tabs[index].focus();
      if (onSelect) onSelect(index);
    }
    tabs.forEach(function (tab, i) {
      tab.addEventListener('click', function () { select(i, false); });
    });
    list.addEventListener('keydown', function (event) {
      var i = tabs.indexOf(document.activeElement);
      if (i < 0) return;
      var keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
      if (keys[event.key]) { event.preventDefault(); select((i + keys[event.key] + tabs.length) % tabs.length, true); }
      if (event.key === 'Home') { event.preventDefault(); select(0, true); }
      if (event.key === 'End') { event.preventDefault(); select(tabs.length - 1, true); }
    });
    return select;
  }
  $$('[data-tabs]').forEach(function (el) {
    var list = $('[role="tablist"]', el);
    tabset(list, $$('[role="tab"]', list), $$('[role="tabpanel"]', el));
  });

  /* ---------------------------------------------------------------- gallery + lightbox */

  var lightbox = $('[data-lightbox]');
  $$('[data-gallery]').forEach(function (el) {
    var list = $('[role="tablist"]', el);
    tabset(list, $$('[role="tab"]', list), $$('.gallery-item', el));
  });
  if (lightbox && lightbox.showModal) {
    var lbImg = $('[data-lightbox-img]', lightbox);
    $$('[data-zoom]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var img = $('img', btn);
        lbImg.src = img.currentSrc || img.src;
        lbImg.alt = img.alt;
        lightbox.showModal();
      });
    });
    $('[data-lightbox-close]', lightbox).addEventListener('click', function () { lightbox.close(); });
    lightbox.addEventListener('click', function (event) { if (event.target === lightbox) lightbox.close(); });
  }

  /* ---------------------------------------------------------------- video */

  $$('[data-video]').forEach(function (frame) {
    var button = $('.video-play', frame);
    button.addEventListener('click', function () {
      var video = document.createElement('video');
      video.src = frame.dataset.src;
      video.controls = true;
      video.autoplay = true;
      video.playsInline = true;
      video.poster = $('img', frame).src;
      frame.replaceChildren(video);
      video.focus();
    });
  });

  /* ---------------------------------------------------------------- download: detect chip */

  var archCards = $$('[data-arch-card]');
  function recommend(arch) {
    archCards.forEach(function (card) {
      var on = card.dataset.archCard === arch;
      card.classList.toggle('is-recommended', on);
      $('[data-arch-badge]', card).hidden = !on;
    });
  }
  function guessArch() {
    try {
      var canvas = document.createElement('canvas');
      var gl = canvas.getContext('webgl');
      var ext = gl && gl.getExtension('WEBGL_debug_renderer_info');
      var renderer = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : '';
      if (/Apple M\d|Apple GPU/i.test(renderer)) return 'arm64';
      if (/Intel|AMD|Radeon|NVIDIA/i.test(renderer)) return 'x86_64';
    } catch (e) {}
    return null;
  }
  if (archCards.length) {
    // Mostly sold today, and the safe default when detection is inconclusive.
    recommend('arm64');
    $$('[data-arch-badge]').forEach(function (b) { b.hidden = true; });
    var applyGuess = function (arch) { if (arch) recommend(arch); };
    if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
      navigator.userAgentData.getHighEntropyValues(['architecture']).then(function (v) {
        applyGuess(v.architecture === 'arm' ? 'arm64' : v.architecture === 'x86' ? 'x86_64' : guessArch());
      }, function () { applyGuess(guessArch()); });
    } else {
      applyGuess(guessArch());
    }
  }

  /* ---------------------------------------------------------------- docs */

  var sidebar = $('[data-docs-sidebar]');
  var sidebarToggle = $('[data-docs-toggle]');
  if (sidebar && sidebarToggle) {
    sidebarToggle.addEventListener('click', function () {
      var open = !sidebar.classList.contains('is-open');
      sidebar.classList.toggle('is-open', open);
      sidebarToggle.setAttribute('aria-expanded', String(open));
    });
  }
  var tocLinks = $$('[data-toc] a');
  if (tocLinks.length && 'IntersectionObserver' in window) {
    var targets = tocLinks.map(function (a) { return document.getElementById(decodeURIComponent(a.hash.slice(1))); }).filter(Boolean);
    var visible = new Set();
    var setActive = function () {
      var active = targets.filter(function (t) { return visible.has(t); })[0];
      if (!active) {
        // Between headings: keep the last one above the viewport.
        for (var i = targets.length - 1; i >= 0; i--) {
          if (targets[i].getBoundingClientRect().top < 120) { active = targets[i]; break; }
        }
      }
      tocLinks.forEach(function (a) {
        a.classList.toggle('is-active', !!active && decodeURIComponent(a.hash.slice(1)) === active.id);
      });
    };
    var tocObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) visible.add(e.target); else visible.delete(e.target); });
      setActive();
    }, { rootMargin: '-72px 0px -65% 0px' });
    targets.forEach(function (t) { tocObserver.observe(t); });
  }

  /* ---------------------------------------------------------------- search */

  var dialog = $('[data-search-dialog]');
  if (dialog && dialog.showModal) {
    var input = $('[data-search-input]', dialog);
    var results = $('[data-search-results]', dialog);
    var empty = $('[data-search-empty]', dialog);
    var index = null;
    var selected = 0;

    var load = function () {
      if (index) return Promise.resolve(index);
      return fetch(dialog.dataset.index).then(function (r) { return r.json(); }).then(function (data) {
        index = data.map(function (e) { e.l = (e.h + ' ' + e.x + ' ' + e.p).toLowerCase(); return e; });
        return index;
      });
    };
    var open = function () {
      if (dialog.open) return;
      dialog.showModal();
      input.select();
      load().then(render);
    };
    var esc = function (s) { return s.replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); };
    var highlight = function (text, terms) {
      var out = esc(text);
      terms.forEach(function (term) {
        if (!term) return;
        var re = new RegExp('(' + term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig');
        out = out.replace(re, '<mark>$1</mark>');
      });
      return out;
    };
    var snippet = function (text, term) {
      var i = term ? text.toLowerCase().indexOf(term) : -1;
      if (i < 0) return text.slice(0, 140);
      var start = Math.max(0, i - 40);
      return (start ? '…' : '') + text.slice(start, start + 150);
    };
    var render = function () {
      var q = input.value.trim().toLowerCase();
      results.replaceChildren();
      empty.hidden = true;
      if (!q || !index) return;
      // CJK has no spaces: treat the whole query as one term unless it has spaces.
      var terms = q.split(/\s+/).filter(Boolean);
      var hits = index.map(function (e) {
        var score = 0;
        for (var i = 0; i < terms.length; i++) {
          var t = terms[i];
          if (e.l.indexOf(t) < 0) return null;
          if (e.h.toLowerCase().indexOf(t) >= 0) score += 10;
          if (e.p.toLowerCase().indexOf(t) >= 0) score += 3;
          score += 1;
        }
        return { e: e, s: score };
      }).filter(Boolean).sort(function (a, b) { return b.s - a.s; }).slice(0, 12);
      if (!hits.length) { empty.hidden = false; return; }
      hits.forEach(function (hit, i) {
        var li = document.createElement('li');
        li.setAttribute('role', 'none');
        var a = document.createElement('a');
        a.href = hit.e.u;
        a.setAttribute('role', 'option');
        a.innerHTML = '<span class="sr-page">' + esc(hit.e.p) + '</span><span class="sr-head">' + highlight(hit.e.h, terms) +
          '</span><span class="sr-text">' + highlight(snippet(hit.e.x, terms[0]), terms) + '</span>';
        a.addEventListener('click', function () { dialog.close(); });
        li.appendChild(a);
        results.appendChild(li);
      });
      selected = 0;
      mark();
    };
    var mark = function () {
      $$('a', results).forEach(function (a, i) {
        a.setAttribute('aria-selected', String(i === selected));
        if (i === selected) a.scrollIntoView({ block: 'nearest' });
      });
    };
    input.addEventListener('input', function () { load().then(render); });
    input.addEventListener('keydown', function (event) {
      var links = $$('a', results);
      if (event.key === 'ArrowDown' && links.length) { event.preventDefault(); selected = (selected + 1) % links.length; mark(); }
      if (event.key === 'ArrowUp' && links.length) { event.preventDefault(); selected = (selected - 1 + links.length) % links.length; mark(); }
      if (event.key === 'Enter' && links[selected]) { event.preventDefault(); dialog.close(); location.href = links[selected].href; }
    });
    $$('[data-search-open]').forEach(function (btn) { btn.addEventListener('click', open); });
    $('[data-search-close]', dialog).addEventListener('click', function () { dialog.close(); });
    dialog.addEventListener('click', function (event) { if (event.target === dialog) dialog.close(); });
    document.addEventListener('keydown', function (event) {
      var typing = /input|textarea|select/i.test((event.target.tagName || '')) || event.target.isContentEditable;
      if ((event.key === 'k' || event.key === 'K') && (event.metaKey || event.ctrlKey)) { event.preventDefault(); open(); }
      else if (event.key === '/' && !typing) { event.preventDefault(); open(); }
    });
  }
})();
