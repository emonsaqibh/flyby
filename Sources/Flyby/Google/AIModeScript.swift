// The JavaScript Flyby injects into the AI Mode page. Kept as raw strings so
// the scripts are bundled with no resource plumbing; the originals are
// developed and tested offline against captured Google pages (see the notes on
// `extractor`).

/// Scripts for `AIModeEngine`'s page. Both run in Flyby's own content world
/// (`AIModeEngine.contentWorld`), so Google's scripts can't see them, and
/// neither can they see `webkit.messageHandlers` — an embedded-web-view tell.
enum AIModeScript {
    /// Document start: captures the `flyby` message handler and sets up
    /// `window.__flyby` (`stop()`, `setReader(_:)`, a per-document `pageId`).
    static let bridge = #"""
// Runs at document start, in Flyby's own content world, before any of the
// page's scripts. Grabs the message handler while the world is pristine and
// gives the extractor (and Swift) one namespace to talk through.
(function () {
  'use strict';
  if (window.__flyby) return;
  var handler = null;
  try { handler = window.webkit.messageHandlers.flyby; } catch (e) {}
  var F = {
    // Distinguishes this document from the one before it, so Swift can drop
    // a late message from a page it has already navigated away from.
    pageId: Math.random().toString(36).slice(2) + Date.now().toString(36),
    stopped: false,
    readerWanted: false,
    post: function (json) {
      if (F.stopped || !handler) return;
      try { handler.postMessage(json); } catch (e) {}
    },
    // Freezes the answer as it stands: no more reads, no more posts.
    stop: function () {
      F.stopped = true;
      if (F.onStop) F.onStop();
    },
    setReader: function (on) {
      F.readerWanted = !!on;
      if (F.onReader) F.onReader();
    }
  };
  window.__flyby = F;
})();
"""#

    /// Document end: reads the answer out of the page and posts a JSON string
    /// (decoded by `AIModeMessage`) whenever it changes.
    ///
    /// What it relies on, all verified against real captures (a live AI Mode
    /// answer from 2026-09-16, Google's CAPTCHA and consent pages):
    /// - answer body: the last `[data-container-id="main-col"]` of the last
    ///   turn (`[data-xid="aim-mars-turn-root"] > [data-tr-rsts]`);
    /// - citations: `button[data-icl-uuid]` chips whose sibling `a[href]`
    ///   carries the source; side cards under `[data-container-id="rhs-col"]`;
    /// - completion: the footer `[data-xid="Gd7Hsc"]` plus 1.3 s without
    ///   change (mid-stream pauses of up to 2.6 s were observed, so quiet alone
    ///   isn't enough), or 10 s without change if the footer never shows;
    /// - CAPTCHA / consent / sign-in from the URL and form/iframe hooks, never
    ///   from English text, so `hl` can follow the user's language.
    /// - follow-ups (live page, 2026-09-28): the composer is the textarea in
    ///   `[data-xid="aim-mars-input-plate"]`, sent with
    ///   `button[data-xid="input-plate-send-button"]`, which stays hidden
    ///   until the page has read text from an `input` event; Google focuses
    ///   the composer after each answer. Each answer is a new
    ///   `[data-tr-rsts]` turn in the same turn root, with its own footer; the
    ///   document stays, and the URL keeps the first question as `q` while
    ///   its `mstk` token changes. Only a page that renders — in a window on
    ///   screen, as Flyby's is while a chat is open — takes more than one
    ///   follow-up: out of any window, the second is ignored.
    ///
    /// `__flyby.followUp(question, turn)` asks a follow-up in the page and
    /// resolves to `"sent"` or the reason it couldn't be; from then on only
    /// the newer turn is read, and every message carries `turn`.
    /// `__flyby.read({href})` returns the payload without posting, for tests.
    static let extractor = #"""
// Runs at document end, in Flyby's own content world. Reads Google AI Mode's
// answer out of the live DOM as it streams and posts it to Swift as JSON in
// AnswerBlock's wire format. Keys on data-* hooks and structure, never on
// Google's obfuscated class names or English UI text, so it survives both a
// restyle and a change of `hl`.
(function () {
  'use strict';

  var F = window.__flyby;
  if (!F) {
    // The document-start bridge didn't run (it always should); make do.
    var handler = null;
    try { handler = window.webkit.messageHandlers.flyby; } catch (e) {}
    F = window.__flyby = {
      pageId: Math.random().toString(36).slice(2),
      stopped: false,
      readerWanted: false,
      post: function (json) { if (!F.stopped && handler) { try { handler.postMessage(json); } catch (e) {} } },
      stop: function () { F.stopped = true; if (F.onStop) F.onStop(); },
      setReader: function (on) { F.readerWanted = !!on; if (F.onReader) F.onReader(); }
    };
  }
  if (F.read) return;

  // Reads are debounced: Google mutates the page in bursts while streaming.
  var DEBOUNCE_MS = 120;
  var MAX_WAIT_MS = 400;
  // The footer arrives with the final text, but side cards can land ~0.5 s
  // later; and mid-stream pauses of 1.5-2.6 s without the footer happen, so
  // quiet time alone never completes an answer unless it's very long.
  var QUIET_MS = 1300;
  var FALLBACK_QUIET_MS = 10000;

  var MAIN = '[data-container-id="main-col"]';
  var RHS = '[data-container-id="rhs-col"]';
  var FOOTER = '[data-xid="Gd7Hsc"]';
  var CHIP = 'button[data-icl-uuid]';
  var SKIP_SEL = FOOTER + ', [data-subtree="aimba"], [data-ignore-copy], ' + RHS + ', [role="button"], [role="toolbar"], [role="progressbar"]';
  var SKIP_TAGS = /^(script|style|noscript|template|svg|img|picture|video|audio|canvas|iframe|button|input|textarea|select|form|dialog|object|embed|link|meta)$/;
  var BLOCK_TAGS = /^(div|p|section|article|main|header|footer|aside|nav|figure|figcaption|details|summary|dl|dt|dd|address|center|fieldset|li)$/;
  var BLOCK_DISPLAY = /^(block|flex|grid|table|list-item|flow-root)$/;
  var BLOCKISH = 'div, p, section, article, ul, ol, table, pre, blockquote, hr, h1, h2, h3, h4, h5, h6, [role="heading"], [role="list"]';
  // English fast paths; other languages fall back to the suffix all labels share.
  var CHIP_SUFFIX = /[.\s]*related results\.?\s*$/i;
  var CARD_SUFFIX = /[.\s]*opens in (a )?new (tab|window)\.?\s*$/i;

  var READER_ATTR = 'data-flyby-reader';
  var R = 'html[' + READER_ATTR + ']';
  var READER_CSS = [
    // Opt the page into the app's theme and let it paint its own background.
    R + ' { color-scheme: light dark; }',
    // Google's page chrome: masthead, tabs, sign-in, left rail, footer.
    [
      'header', '[role="banner"]', '[role="navigation"]', '[role="search"]',
      '[role="complementary"]', 'footer', '#searchform', '#gb', '#gbw', '#footcnt',
      '#before-appbar', '#appbar', '#topabar', '#hdtb', '#hdtbSum', '#sfooter',
      'a[href*="accounts.google.com"]', '[data-reader-hide="1"]', '[data-reader-query="1"]',
      'img[alt="Google"]', 'img[src*="googlelogo"]'
    ].map(function (s) { return R + ' ' + s; }).join(',\n') + ' { display: none !important; }',
    R + ' body { padding: 4px 6px 16px !important; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important; }',
    // Reclaim the horizontal space the hidden rail was holding.
    ['#main', '#cnt', '#center_col', '#rcnt', '[role="main"]'].map(function (s) { return R + ' ' + s; }).join(', ') +
      ' { margin-left: 0 !important; padding-left: 0 !important; max-width: 100% !important; width: 100% !important; }'
  ].join('\n');

  // MARK: - Small helpers

  function norm(s) { return String(s || '').replace(/[\s\u00a0]+/g, ' ').trim(); }

  function isGoogleHost(host) {
    return /(^|\.)google\.(com|[a-z]{2,3})(\.[a-z]{2})?$/i.test(host || '');
  }

  function hostOf(url) {
    try { return new URL(url).hostname.replace(/^www\./, ''); } catch (e) { return url; }
  }

  // Absolute http(s) URL, Google's /url?q= redirect unwrapped and any
  // #:~:text= fragment directive dropped; null for anything else. /goto?url=
  // is opaque (encrypted), so it stays an absolute Google URL.
  function cleanURL(raw, base) {
    if (!raw) return null;
    var u;
    try { u = new URL(raw, base); } catch (e) { return null; }
    if (isGoogleHost(u.hostname) && u.pathname === '/url') {
      var inner = u.searchParams.get('q') || u.searchParams.get('url');
      if (inner) {
        try { u = new URL(inner); } catch (e) { return null; }
      }
    }
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
    var i = u.hash.indexOf(':~:');
    if (i >= 0) u.hash = i > 1 ? u.hash.slice(1, i) : '';
    return u.href;
  }

  // Inline markdown is what the native view parses, so page text that happens
  // to contain markdown syntax has to be escaped to stay literal.
  function esc(s) {
    return s
      .replace(/[\\`*\[\]~<]/g, '\\$&')
      .replace(/&(?=#?[A-Za-z0-9]+;)/g, '\\&')
      .replace(/_/g, function (m, i, str) {
        return /[A-Za-z0-9]/.test(str.charAt(i - 1)) && /[A-Za-z0-9]/.test(str.charAt(i + 1)) ? '_' : '\\_';
      });
  }

  function mdURL(url) {
    return url.replace(/[()<> ]/g, function (c) { return '%' + c.charCodeAt(0).toString(16).toUpperCase(); });
  }

  // Collapses whitespace; U+2028 stands in for <br> until here.
  function tidy(s) {
    return s
      .replace(/[\u200b\ufeff]/g, '')
      .replace(/[ \t\r\n\f\u00a0]+/g, ' ')
      .replace(/ ?\u2028 ?/g, '\n')
      .trim();
  }

  function wrap(mark, inner) {
    var m = /^(\s*)([\s\S]*?)(\s*)$/.exec(inner);
    if (!m[2]) return inner;
    return m[1] + mark + m[2] + mark + m[3];
  }

  function codeSpan(text) {
    var t = text.replace(/[\s\u00a0]+/g, ' ');
    if (!t.trim()) return '';
    return t.indexOf('`') >= 0 ? '`` ' + t + ' ``' : '`' + t + '`';
  }

  // Wrappers use display:contents, so checkVisibility() would call visible
  // content hidden. Computed display/visibility is what actually matters.
  function hidden(el) {
    if (el.hidden || el.getAttribute('aria-hidden') === 'true') return true;
    var cs = getComputedStyle(el);
    return cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse';
  }

  function rendered(el) {
    for (var n = el; n && n.nodeType === 1; n = n.parentElement) {
      if (getComputedStyle(n).display === 'none') return false;
    }
    return getComputedStyle(el).visibility !== 'hidden';
  }

  function skip(el) {
    if (SKIP_TAGS.test(el.localName)) return true;
    if (el.matches(SKIP_SEL)) return true;
    return hidden(el);
  }

  // MARK: - Citations

  // A citation chip is <span><a href aria-label="Site (+N) – Title. Related
  // results"></a><button data-icl-uuid>…</button></span>. The anchor carries
  // the source; a chip with no anchor is an icon-only chip (hidden) — skipped.
  function chipButtonFor(a) {
    return a.parentElement ? a.parentElement.querySelector(':scope > ' + CHIP) : null;
  }

  function chipAnchorFor(button) {
    return button.parentElement ? button.parentElement.querySelector(':scope > a[href]') : null;
  }

  // Returns true when `el` was part of a chip (and is consumed either way).
  function takeChip(el, acc) {
    var a = null, button = null;
    if (el.localName === 'a' && el.hasAttribute('href')) {
      button = chipButtonFor(el);
      if (!button) return false;
      a = el;
    } else if (el.matches(CHIP)) {
      button = el;
      a = chipAnchorFor(el);
      if (!a) return true;
    } else {
      return false;
    }
    if (hidden(button)) return true;
    var url = cleanURL(a.getAttribute('href'), acc.base);
    if (!url) return true;
    acc.chips.push({
      url: url,
      label: norm(a.getAttribute('aria-label') || button.getAttribute('aria-label')),
      site: norm(button.textContent).replace(/\s*\+\s*\d+$/, '')
    });
    return true;
  }

  // MARK: - Inline content

  function kidsInline(el, acc, ctx) {
    var out = '';
    for (var n = el.firstChild; n; n = n.nextSibling) out += inline(n, acc, ctx);
    return out;
  }

  function derive(ctx, key) {
    var next = {};
    for (var k in ctx) next[k] = ctx[k];
    next[key] = true;
    return next;
  }

  function inline(node, acc, ctx) {
    if (node.nodeType === 3) return esc(node.data);
    if (node.nodeType !== 1) return '';
    var el = node;
    if (takeChip(el, acc)) return '';
    if (el.localName === 'br') return '\u2028';
    if (skip(el)) return '';

    var name = el.localName;
    var role = el.getAttribute('role');
    // Structure inside a list item is lifted out and emitted after it.
    if (ctx.nested && (name === 'ul' || name === 'ol' || role === 'list' || name === 'table' || name === 'pre' || name === 'blockquote')) {
      ctx.nested.push(el);
      return ' ';
    }
    switch (name) {
      case 'strong':
      case 'b':
        return ctx.bold ? kidsInline(el, acc, ctx) : wrap('**', kidsInline(el, acc, derive(ctx, 'bold')));
      case 'em':
      case 'i':
      case 'cite':
      case 'dfn':
        return ctx.italic ? kidsInline(el, acc, ctx) : wrap('*', kidsInline(el, acc, derive(ctx, 'italic')));
      case 'code':
      case 'kbd':
      case 'samp':
      case 'tt':
        return codeSpan(el.textContent);
      case 'a': {
        var text = kidsInline(el, acc, derive(ctx, 'link'));
        if (!text.trim()) return '';
        var url = ctx.link ? null : cleanURL(el.getAttribute('href'), acc.base);
        if (!url) return text;
        var m = /^(\s*)([\s\S]*?)(\s*)$/.exec(text);
        return m[1] + '[' + m[2] + '](' + mdURL(url) + ')' + m[3];
      }
      case 'pre':
        return ' ' + codeSpan(el.textContent) + ' ';
      case 'li':
      case 'tr':
        return ' ' + kidsInline(el, acc, ctx) + ' ';
      case 'td':
      case 'th':
        return ' ' + kidsInline(el, acc, ctx) + ' ';
    }
    if (BLOCK_TAGS.test(name) || role === 'heading' || /^h[1-6]$/.test(name)) {
      return ' ' + kidsInline(el, acc, ctx) + ' ';
    }
    return kidsInline(el, acc, ctx);
  }

  // MARK: - Blocks

  function hasBlockInside(el) {
    var found = el.querySelectorAll(BLOCKISH);
    for (var i = 0; i < found.length; i++) {
      var b = found[i].parentElement && found[i].parentElement.closest('button, [role="button"]');
      if (!b || !el.contains(b)) return true;
    }
    return false;
  }

  function kindOf(el) {
    var name = el.localName;
    var role = el.getAttribute('role');
    if (role === 'heading' || /^h[1-6]$/.test(name)) return 'heading';
    if (name === 'ul' || name === 'ol' || role === 'list') return 'list';
    if (name === 'table') return 'table';
    if (name === 'pre') return 'code';
    if (name === 'blockquote') return 'quote';
    if (name === 'hr') return 'divider';
    if (BLOCK_TAGS.test(name)) return 'block';
    if (BLOCK_DISPLAY.test(getComputedStyle(el).display)) return 'block';
    if (hasBlockInside(el)) return 'block';
    return 'inline';
  }

  function blocksOf(el, out, acc) {
    var buf = '';
    function flush() {
      var t = tidy(buf);
      buf = '';
      if (t) out.push({ type: 'paragraph', text: t });
    }
    for (var n = el.firstChild; n; n = n.nextSibling) {
      if (n.nodeType === 3) { buf += esc(n.data); continue; }
      if (n.nodeType !== 1) continue;
      if (takeChip(n, acc)) continue;
      if (n.localName === 'br') { buf += '\u2028'; continue; }
      if (skip(n)) continue;
      var kind = kindOf(n);
      if (kind === 'inline') { buf += inline(n, acc, {}); continue; }
      flush();
      emit(kind, n, out, acc, 0);
    }
    flush();
  }

  function emit(kind, el, out, acc, depth) {
    switch (kind) {
      case 'heading': {
        var aria = parseInt(el.getAttribute('aria-level'), 10);
        var tag = /^h([1-6])$/.exec(el.localName);
        var level = aria > 0 ? aria : tag ? Number(tag[1]) : 2;
        var text = tidy(kidsInline(el, acc, {})).replace(/\n+/g, ' ');
        if (text) out.push({ type: 'heading', level: Math.min(Math.max(level, 1), 6), text: text });
        return;
      }
      case 'list': return listBlocks(el, depth, out, acc);
      case 'table': {
        var table = tableBlock(el, acc);
        if (table) out.push(table);
        return;
      }
      case 'code': {
        var code = codeBlock(el, out);
        if (code) out.push(code);
        return;
      }
      case 'quote': {
        var q = tidy(kidsInline(el, acc, {}));
        if (q) out.push({ type: 'quote', text: q });
        return;
      }
      case 'divider':
        out.push({ type: 'divider' });
        return;
      default:
        blocksOf(el, out, acc);
    }
  }

  function listItems(list) {
    var role = list.getAttribute('role');
    var items = [];
    for (var c = list.firstElementChild; c; c = c.nextElementSibling) {
      if (role === 'list' ? c.getAttribute('role') === 'listitem' : c.localName === 'li') items.push(c);
    }
    return items;
  }

  function listBlocks(list, depth, out, acc) {
    var ordered = list.localName === 'ol';
    var n = ordered ? (parseInt(list.getAttribute('start'), 10) || 1) : 0;
    var items = listItems(list);
    for (var i = 0; i < items.length; i++) {
      var li = items[i];
      if (skip(li)) continue;
      var nested = [];
      var text = tidy(kidsInline(li, acc, { nested: nested }));
      var childDepth = depth;
      // Empty <li> spacers (Google pads lists with them) aren't items.
      if (text) {
        out.push({ type: 'listItem', ordered: ordered, marker: ordered ? (n++) + '.' : '\u2022', depth: depth, text: text });
        childDepth = depth + 1;
      }
      for (var k = 0; k < nested.length; k++) {
        var kind = kindOf(nested[k]);
        emit(kind, nested[k], out, acc, kind === 'list' ? childDepth : depth);
      }
    }
  }

  function tableBlock(table, acc) {
    var header = null;
    var rows = [];
    var trs = table.querySelectorAll('tr');
    for (var i = 0; i < trs.length; i++) {
      var tr = trs[i];
      if (tr.closest('table') !== table || skip(tr)) continue;
      var cells = [];
      var allHeader = true;
      for (var c = tr.firstElementChild; c; c = c.nextElementSibling) {
        if ((c.localName !== 'td' && c.localName !== 'th') || skip(c)) continue;
        cells.push(tidy(kidsInline(c, acc, {})).replace(/\n+/g, ' '));
        if (c.localName !== 'th') allHeader = false;
      }
      if (!cells.length) continue;
      var inHead = tr.parentElement && tr.parentElement.localName === 'thead';
      if (header === null && rows.length === 0 && (allHeader || inHead)) header = cells;
      else rows.push(cells);
    }
    if (header === null) {
      if (!rows.length) return null;
      header = rows.shift();
    }
    return { type: 'table', header: header, rows: rows };
  }

  // Text of a <pre>, keeping line structure even when each line is its own
  // element rather than a newline, and leaving out copy buttons and the like.
  function codeText(el) {
    var out = '';
    function walk(node) {
      for (var n = node.firstChild; n; n = n.nextSibling) {
        if (n.nodeType === 3) { out += n.data; continue; }
        if (n.nodeType !== 1) continue;
        if (n.localName === 'br') { out += '\n'; continue; }
        if (SKIP_TAGS.test(n.localName) || n.getAttribute('role') === 'button' || n.getAttribute('aria-hidden') === 'true') continue;
        var line = n.localName === 'div' || n.localName === 'p' || n.localName === 'li';
        if (line && out && out.charAt(out.length - 1) !== '\n') out += '\n';
        walk(n);
        if (line && out && out.charAt(out.length - 1) !== '\n') out += '\n';
      }
    }
    walk(el);
    return out.replace(/\u00a0/g, ' ').replace(/\n+$/, '');
  }

  function codeLanguage(pre) {
    var holders = [pre.querySelector('code'), pre, pre.parentElement];
    for (var i = 0; i < holders.length; i++) {
      var h = holders[i];
      if (!h) continue;
      var cls = typeof h.className === 'string' ? h.className : '';
      var m = /(?:^|\s)(?:language|lang)-([\w+#.-]+)/.exec(cls);
      if (m) return m[1];
      var attr = h.getAttribute('data-language') || h.getAttribute('data-lang');
      if (attr) return attr;
    }
    return null;
  }

  function codeBlock(pre, out) {
    var text = codeText(pre);
    if (!text.trim()) return null;
    var language = codeLanguage(pre);
    // Code blocks usually sit under a one-word caption ("Python") next to the
    // <pre>; that came out as its own paragraph just now — fold it back in.
    var prev = out[out.length - 1];
    if (prev && prev.type === 'paragraph' && /^[\w+#.-]{1,20}$/.test(prev.text)) {
      var sib = pre.previousElementSibling || (pre.parentElement && pre.parentElement.previousElementSibling);
      if (sib && norm(sib.textContent).indexOf(prev.text.replace(/\\/g, '')) >= 0) {
        out.pop();
        if (!language) language = prev.text.replace(/\\/g, '');
      }
    }
    return { type: 'code', language: language, text: text };
  }

  function cleanBlocks(blocks) {
    var out = [];
    for (var i = 0; i < blocks.length; i++) {
      var b = blocks[i];
      if (b.type === 'divider' && (!out.length || out[out.length - 1].type === 'divider')) continue;
      out.push(b);
    }
    while (out.length && out[out.length - 1].type === 'divider') out.pop();
    return out;
  }

  // MARK: - Sources

  // The part every label shares at the end — a localized "Related results" or
  // "Opens in new tab" — cut back to a word boundary. Needs two distinct
  // labels to mean anything.
  function commonSuffix(labels) {
    var seen = {};
    var uniq = [];
    for (var i = 0; i < labels.length; i++) {
      var l = labels[i].toLowerCase();
      if (l && !seen[l]) { seen[l] = true; uniq.push(l); }
    }
    if (uniq.length < 2) return '';
    var s = uniq[0];
    for (var k = 1; k < uniq.length; k++) {
      var t = uniq[k];
      var n = 0;
      while (n < s.length && n < t.length && s.charAt(s.length - 1 - n) === t.charAt(t.length - 1 - n)) n++;
      s = s.slice(s.length - n);
    }
    var m = /[\s.\u3002\uff0e,\uff0c:\uff1a;|\u2013\u2014-]/.exec(s);
    if (!m) return '';
    s = s.slice(m.index);
    return /[^\s.\u3002\uff0e,\uff0c:\uff1a;|\u2013\u2014-]{3}/.test(s) ? s : '';
  }

  function stripSuffix(label, re, suffix) {
    var t = label.replace(re, '');
    if (t === label && suffix && label.toLowerCase().slice(-suffix.length) === suffix) {
      t = label.slice(0, label.length - suffix.length);
    }
    if (t !== label) t = t.replace(/[\s.,:;|\u2013\u2014-]+$/, '');
    return t.trim();
  }

  function parseChip(chip, suffix) {
    var t = stripSuffix(chip.label, CHIP_SUFFIX, suffix);
    var site = '';
    var title = '';
    var m = /^(.*?)\s+[\u2013\u2014]\s+([\s\S]*)$/.exec(t);
    if (m) {
      site = m[1];
      title = m[2];
    } else if (chip.site && t.replace(/\s*\(\+\d+\)\s*$/, '').toLowerCase() === chip.site.toLowerCase()) {
      site = t;
    } else {
      title = t;
    }
    site = norm(site.replace(/\s*\(\+\s*\d+\)\s*$/, '')) || chip.site;
    return { title: norm(title), site: site };
  }

  function cardTitle(card, a, label, suffix) {
    if (label) {
      // Prefer the piece of visible card text the label starts with: it's the
      // title in whatever language the page is in.
      var best = '';
      var els = card.querySelectorAll('*');
      for (var i = 0; i < els.length; i++) {
        if (els[i].children.length > 4) continue;
        var t = norm(els[i].textContent);
        if (t.length >= 6 && t.length > best.length && t.length < label.length && label.indexOf(t) === 0) best = t;
      }
      if (best) return best;
      return stripSuffix(label, CARD_SUFFIX, suffix);
    }
    var heading = card.querySelector('[role="heading"], h3, h4');
    return norm((heading || a).textContent).slice(0, 300);
  }

  function buildSources(acc, scope) {
    var out = [];
    var byURL = {};
    function add(url, title, site) {
      var s = byURL[url];
      if (s) {
        if (!s.title && title) s.title = title;
        if (!s.siteName && site) s.siteName = site;
        return;
      }
      s = { title: title || '', url: url, siteName: site || null };
      byURL[url] = s;
      out.push(s);
    }

    var chipSuffix = commonSuffix(acc.chips.map(function (c) { return c.label; }).filter(function (l) { return !CHIP_SUFFIX.test(l); }));
    acc.chips.forEach(function (c) {
      var p = parseChip(c, chipSuffix);
      add(c.url, p.title, p.site);
    });

    var cards = [];
    var nodes = scope.querySelectorAll(RHS + ' [data-src-id]');
    for (var i = 0; i < nodes.length; i++) {
      var card = nodes[i];
      var a = card.matches('a[href]') ? card : card.querySelector('a[href^="http"], a[href^="/url"]');
      if (!a) continue;
      var url = cleanURL(a.getAttribute('href'), acc.base);
      if (!url) continue;
      cards.push({ card: card, a: a, url: url, label: norm(a.getAttribute('aria-label')) });
    }
    var cardSuffix = commonSuffix(cards.map(function (c) { return c.label; }).filter(function (l) { return !CARD_SUFFIX.test(l); }));
    cards.forEach(function (c) { add(c.url, cardTitle(c.card, c.a, c.label, cardSuffix), null); });

    out.forEach(function (s) { if (!s.title) s.title = s.siteName || hostOf(s.url); });
    return out;
  }

  // MARK: - Page

  function outermost(list) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var p = list[i].parentElement;
      if (!p || !p.closest(MAIN)) out.push(list[i]);
    }
    return out;
  }

  function turnsOf() {
    var turns = document.querySelectorAll('[data-xid="aim-mars-turn-root"] > [data-tr-rsts]');
    if (!turns.length) turns = document.querySelectorAll('[data-xid="aim-mars-turn-root"] [data-tr-rsts]');
    return turns;
  }

  // Answers on the page so far: turns, and answer bodies in case the turn
  // markup is ever gone.
  function answerCount() {
    return { turns: turnsOf().length, mains: outermost(document.querySelectorAll(MAIN)).length };
  }

  // Set while a follow-up asked in the page is being answered: what was on
  // the page when it was sent. Everything up to there is an earlier answer,
  // and must never be read as this one.
  var base = null;

  // The answer body is the last turn's last main-col. A new turn that has no
  // answer yet means "loading", not "show the previous turn's answer".
  function findRoot() {
    var turns = turnsOf();
    if (base) {
      if (base.turns) {
        if (turns.length <= base.turns) return null;
        var fresh = outermost(turns[turns.length - 1].querySelectorAll(MAIN));
        return fresh.length ? fresh[fresh.length - 1] : null;
      }
      var bodies = outermost(document.querySelectorAll(MAIN));
      return bodies.length > base.mains ? bodies[bodies.length - 1] : null;
    }
    if (turns.length) {
      var mains = outermost(turns[turns.length - 1].querySelectorAll(MAIN));
      if (mains.length) return mains[mains.length - 1];
      for (var t = 0; t < turns.length - 1; t++) {
        if (turns[t].querySelector(MAIN)) return null;
      }
    }
    var inAimc = outermost(document.querySelectorAll('[data-subtree="aimc"] ' + MAIN));
    if (inAimc.length) return inAimc[inAimc.length - 1];
    var all = outermost(document.querySelectorAll(MAIN));
    return all.length ? all[all.length - 1] : null;
  }

  function scopeOf(root) {
    return root.closest('[data-scope-id="turn"]') || root.closest('[data-tr-rsts]') ||
      root.closest('[data-subtree="aimc"]') || document;
  }

  function footerDone(root) {
    var scope = root.closest('[data-scope-id="turn"]') || root.closest('[data-tr-rsts]') ||
      root.closest('[data-subtree="aimc"]') || root;
    var footer = scope.querySelector(FOOTER);
    return !!(footer && footer.querySelector('button, [role="button"]') && rendered(footer));
  }

  function captchaKind(host, path) {
    if (isGoogleHost(host) && /^\/sorry(\/|$)/.test(path)) return 'captcha';
    if (document.querySelector('form#captcha-form, form[action*="/sorry/"], .g-recaptcha[data-sitekey]')) return 'captcha';
    var frames = document.querySelectorAll('iframe[src*="/recaptcha/enterprise/"]');
    for (var i = 0; i < frames.length; i++) {
      if (!/size=invisible/.test(frames[i].getAttribute('src'))) return 'captcha';
    }
    return null;
  }

  function consentKind(host, hasAnswer) {
    if (/^consent\./.test(host) && isGoogleHost(host)) return 'consent';
    var forms = document.querySelectorAll('form[action^="https://consent.google."]');
    for (var i = 0; i < forms.length; i++) {
      var f = forms[i];
      if (!rendered(f)) continue;
      if (f.closest('[aria-modal="true"]') || !hasAnswer) return 'consent';
    }
    return null;
  }

  function accountState() {
    var a = document.querySelector('a[href*="accounts.google.com/SignOutOptions"]');
    if (a) return { signedIn: true, label: a.getAttribute('aria-label') || null };
    if (document.querySelector('a[href*="accounts.google.com/ServiceLogin"], a[href*="accounts.google.com/v3/signin"], a[href*="accounts.google.com/InteractiveLogin"]')) {
      return { signedIn: false, label: null };
    }
    return { signedIn: null, label: null };
  }

  // MARK: - Snapshot

  var lastSig = null;
  var lastChangeAt = 0;
  var doneRoot = null;

  function compute(opts) {
    var href = opts.href || location.href;
    var url = null;
    try { url = new URL(href); } catch (e) {}
    var web = !!url && (url.protocol === 'https:' || url.protocol === 'http:');
    var base = web ? url.href : 'https://www.google.com/';
    var host = web ? url.hostname.toLowerCase() : '';
    var path = web ? url.pathname : '';

    // Our own reader stylesheet mustn't read as "hidden" to the extractor.
    var docEl = document.documentElement;
    var readerOn = docEl.hasAttribute(READER_ATTR);
    if (readerOn) docEl.removeAttribute(READER_ATTR);
    try {
      var kind = captchaKind(host, path);
      var blocks = [];
      var sources = [];
      var root = null;
      if (!kind) {
        root = findRoot();
        if (root) {
          var acc = { base: base, chips: [] };
          blocksOf(root, blocks, acc);
          blocks = cleanBlocks(blocks);
          sources = buildSources(acc, scopeOf(root));
        }
        kind = consentKind(host, blocks.length > 0 || !!base) ||
          (/^accounts\./.test(host) && isGoogleHost(host) ? 'signIn' : null);
        if (kind) { blocks = []; sources = []; root = null; }
      }

      var now = Date.now();
      var sig = JSON.stringify([blocks, sources]);
      if (sig !== lastSig) { lastSig = sig; lastChangeAt = now; }
      var complete = false;
      var recheck = 0;
      if (blocks.length) {
        if (root === doneRoot) {
          complete = true;
        } else if (footerDone(root)) {
          var left = QUIET_MS - (now - lastChangeAt);
          if (left <= 0) { complete = true; doneRoot = root; } else recheck = left;
        } else {
          var left2 = FALLBACK_QUIET_MS - (now - lastChangeAt);
          if (left2 <= 0) complete = true; else recheck = left2;
        }
      }

      var account = kind ? { signedIn: null, label: null } : accountState();
      return {
        payload: {
          v: 1,
          pageId: F.pageId,
          turn: F.turn,
          kind: kind || (blocks.length ? 'answer' : 'loading'),
          blocks: blocks,
          sources: sources,
          followUps: [],
          isComplete: complete,
          signedIn: account.signedIn,
          accountLabel: account.label
        },
        recheck: recheck
      };
    } finally {
      if (readerOn) docEl.setAttribute(READER_ATTR, '');
    }
  }

  // MARK: - Reader mode (only while the page itself is on screen)

  var lastReaderScan = 0;

  // Anything pinned to the viewport is chrome, not content — that's how the
  // composer and cookie banners present themselves.
  function hidePinnedElements() {
    var viewportHeight = window.innerHeight;
    var all = document.querySelectorAll('body *');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.getAttribute('data-reader-hide') === '1') continue;
      var position = getComputedStyle(el).position;
      if (position !== 'fixed' && position !== 'sticky') continue;
      var rect = el.getBoundingClientRect();
      if (rect.height === 0 || rect.height > viewportHeight * 0.9) continue;
      el.setAttribute('data-reader-hide', '1');
    }
  }

  // AI Mode echoes the query as a bubble above the answer; Flyby's own bubble
  // already shows it. Only on a page with one answer: on a conversation the
  // echoes are what separate the answers, and the URL's `q` stays the first
  // question however many follow-ups are asked.
  function hideQueryEcho() {
    if (turnsOf().length > 1) return;
    var query = new URLSearchParams(location.search).get('q');
    if (!query) return;
    var needle = query.trim().toLowerCase();
    var els = document.querySelectorAll('body div, body span, body h1, body h2');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.getAttribute('data-reader-query') === '1' || el.children.length > 1) continue;
      if ((el.textContent || '').trim().toLowerCase() !== needle) continue;
      var node = el;
      for (var k = 0; k < 3 && node.parentElement; k++) {
        if ((node.parentElement.textContent || '').trim().toLowerCase() !== needle) break;
        node = node.parentElement;
      }
      node.setAttribute('data-reader-query', '1');
    }
  }

  function applyReader(kind) {
    var docEl = document.documentElement;
    var on = !!F.readerWanted && (kind === 'answer' || kind === 'loading');
    if (!on) {
      docEl.removeAttribute(READER_ATTR);
      return;
    }
    if (!document.getElementById('flyby-reader-style')) {
      var style = document.createElement('style');
      style.id = 'flyby-reader-style';
      style.textContent = READER_CSS;
      (document.head || docEl).appendChild(style);
    }
    docEl.setAttribute(READER_ATTR, '');
    var now = Date.now();
    if (now - lastReaderScan > 1000) {
      lastReaderScan = now;
      hidePinnedElements();
      hideQueryEcho();
    }
  }

  // MARK: - Scheduling

  var lastJSON = null;
  var debounceTimer = 0;
  var firstPendingAt = 0;
  var recheckTimer = 0;

  function tick() {
    debounceTimer = 0;
    if (F.stopped) return;
    var result;
    try {
      result = compute({});
    } catch (e) {
      result = { payload: { v: 1, pageId: F.pageId, turn: F.turn, kind: 'loading', blocks: [], sources: [], followUps: [], isComplete: false, signedIn: null, accountLabel: null, error: String(e && e.message || e) }, recheck: 0 };
    }
    try { applyReader(result.payload.kind); } catch (e) {}
    var json = JSON.stringify(result.payload);
    if (json !== lastJSON) {
      lastJSON = json;
      F.post(json);
    }
    clearTimeout(recheckTimer);
    recheckTimer = result.recheck > 0 ? setTimeout(schedule, result.recheck + 25) : 0;
  }

  function schedule() {
    if (F.stopped) return;
    var now = Date.now();
    if (debounceTimer) clearTimeout(debounceTimer); else firstPendingAt = now;
    var wait = Math.max(0, Math.min(DEBOUNCE_MS, firstPendingAt + MAX_WAIT_MS - now));
    debounceTimer = setTimeout(tick, wait);
  }

  var observer = new MutationObserver(schedule);
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true,
    attributes: true,
    attributeFilter: ['style', 'class', 'hidden', 'aria-hidden', 'href', 'aria-label', 'data-complete']
  });

  // MARK: - Follow-ups

  var PLATE = '[data-xid="aim-mars-input-plate"]';
  var SEND = 'button[data-xid="input-plate-send-button"]';

  // Which question the page is answering: 0 for the one it loaded with, then
  // the number Swift gives each follow-up. Swift drops messages about any
  // other, so a read that was already on its way can't land on a new turn.
  F.turn = 0;

  function sleep(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }

  async function waitUntil(test, ms) {
    var end = Date.now() + ms;
    while (!test()) {
      if (Date.now() > end) return false;
      await sleep(50);
    }
    return true;
  }

  // Shown and enabled: the send button is hidden while the composer is empty
  // (and keeps no `disabled` then), and appears once the page has read some
  // text from it.
  function ready(button) {
    return !button.disabled && button.getAttribute('aria-disabled') !== 'true' &&
      getComputedStyle(button).display !== 'none';
  }

  // Puts text in the composer the way typing does: through the prototype's
  // value setter, which a framework tracking the field's value can't miss,
  // then the input event the page's own listeners wait for.
  function typeInto(box, text) {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(box, text);
    box.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
  }

  // MARK: - Attaching a screenshot

  function fileFrom(opts) {
    var bytes = atob(opts.image);
    var array = new Uint8Array(bytes.length);
    for (var i = 0; i < bytes.length; i++) array[i] = bytes.charCodeAt(i);
    return new File([array], opts.imageName || 'Screenshot.jpg',
                    { type: opts.imageType || 'image/jpeg', lastModified: Date.now() });
  }

  // Pictures drawn around the composer: a page shows one as soon as it has
  // a file. Counted a level up too, since a preview can sit just above the
  // plate rather than in it.
  function previews(plate) {
    var scope = plate.parentElement || plate;
    var n = 0;
    var els = scope.querySelectorAll('img, [style*="background-image"]');
    for (var i = 0; i < els.length; i++) if (rendered(els[i])) n++;
    return n;
  }

  // Puts the screenshot in the composer, trying what a user would do, in
  // order: Google's own file input (Flyby answers the file picker it opens
  // with the screenshot — the click has to come before anything is awaited,
  // or WebKit won't open a picker for it); the file handed to that input
  // directly; a paste into the composer. Each counts only if a preview
  // appears. Resolves to 'attached (<how>)' or 'not-attached (<why>)'.
  async function attach(plate, opts) {
    var before = previews(plate);
    function shown() { return previews(plate) > before; }
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input[type=file]'));
    inputs.sort(function (a, b) { return (plate.contains(b) ? 1 : 0) - (plate.contains(a) ? 1 : 0); });
    var input = inputs[0] || null;

    if (input) {
      try { input.click(); } catch (e) {}
      if (await waitUntil(shown, 5000)) return 'attached (picker)';
    }
    var file = fileFrom(opts);
    if (input && !F.stopped) {
      try {
        var given = new DataTransfer();
        given.items.add(file);
        input.files = given.files;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      } catch (e) {}
      if (await waitUntil(shown, 5000)) return 'attached (input)';
    }
    var box = plate.querySelector('textarea');
    if (box && !F.stopped) {
      try {
        var pasted = new DataTransfer();
        pasted.items.add(file);
        box.dispatchEvent(new ClipboardEvent('paste', { clipboardData: pasted, bubbles: true, cancelable: true }));
      } catch (e) {}
      if (await waitUntil(shown, 5000)) return 'attached (paste)';
    }
    return 'not-attached (' + inputs.length + ' file inputs)';
  }

  // MARK: - Asking in the composer

  // Asks `question` in AI Mode's own composer, so Google answers it in this
  // conversation. Resolves to 'sent' once the page has taken it, or to why it
  // couldn't be sent — then Swift asks some other way, and the composer is
  // left empty.
  //
  // `opts.fresh`: the page is AI Mode's start page, with no conversation on
  // it yet. `opts.image` (base64, with `imageName` and `imageType`): a
  // screenshot to attach before the question is typed.
  F.followUp = async function (question, turn, opts) {
    opts = opts || {};
    if (F.stopped) return 'stopped';
    var plate = document.querySelector(PLATE);
    var box = plate && plate.querySelector('textarea');
    var send = plate && plate.querySelector(SEND);
    if (!box || !send) return 'no-composer';
    var before = answerCount();
    if (!opts.fresh && !before.turns && !before.mains) return 'no-answer-on-page';

    base = before;
    F.turn = turn;
    lastSig = null;
    lastChangeAt = Date.now();
    doneRoot = null;
    lastJSON = null;
    schedule();

    function taken() {
      var now = answerCount();
      return now.turns > base.turns || now.mains > base.mains;
    }

    // Reader mode hides the composer (it's pinned chrome), and a hidden field
    // can't be focused. It's off by now — a new question hides the page — but
    // only on the next read; the next read puts it back if it's wanted.
    document.documentElement.removeAttribute(READER_ATTR);

    // The picture first, as a user adds it before typing. Nothing awaited
    // before this: see attach().
    var attached = null;
    if (opts.image) {
      attached = await attach(plate, opts);
      if (attached.indexOf('attached') !== 0) return attached;
      if (F.stopped) return 'stopped';
    }

    // As a user would: into the composer first — Google focuses it after
    // each answer, but a click around the revealed page moves focus
    // elsewhere. Emptied, so a leftover draft can't ride along, then typed;
    // the pauses let the page's own handlers run.
    var focused = document.activeElement !== box;
    if (focused) { try { box.focus({ preventScroll: true }); } catch (e) {} }
    typeInto(box, '');
    await waitUntil(function () { return !ready(send); }, 500);
    typeInto(box, question);
    await sleep(150);
    // With a picture, Send waits for its upload.
    await waitUntil(function () { return ready(send); }, attached ? 15000 : 1500);
    if (F.stopped) return 'stopped';

    var how = ready(send) ? 'click' : 'return';
    if (how === 'click') send.click();
    var sent = how === 'click' && await waitUntil(taken, 1500);
    if (!sent && how === 'click' && send.disabled) {
      // The button disables itself when the page takes a question: it's on
      // its way, so Return now would ask it twice.
      sent = await waitUntil(taken, 3000);
    }
    if (!sent && !F.stopped) {
      // Return in the composer is the other way the page sends.
      box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
      how += '+return';
      sent = await waitUntil(taken, 3000);
    }
    if (!sent) {
      typeInto(box, '');
      if (focused) { try { box.blur(); } catch (e) {} }
      return 'not-sent (' + how + ', send ' + (ready(send) ? 'ready' : 'not ready') + (attached ? ', ' + attached : '') + ')';
    }
    return 'sent';
  };

  F.onStop = function () {
    observer.disconnect();
    clearTimeout(debounceTimer);
    clearTimeout(recheckTimer);
    debounceTimer = 0;
    recheckTimer = 0;
  };
  F.onReader = schedule;
  F.read = function (opts) { return compute(opts || {}).payload; };
  // Re-sends the current state even if it hasn't changed.
  F.poke = function () { lastJSON = null; schedule(); };

  window.addEventListener('load', schedule);
  window.addEventListener('pageshow', function (e) { if (e.persisted) F.poke(); });
  tick();
})();
"""#
}
