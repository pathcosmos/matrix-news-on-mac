// Matrix News — web MVP.
// Fetches latest.json from the same repo and renders Korean Matrix rain
// with a typewriter headline overlay. Visual params mirror the SwiftUI app.

const DATA_URL_DEFAULT =
  'https://raw.githubusercontent.com/pathcosmos/matrix-news-on-mac/main/Data/latest.json';
const REFRESH_INTERVAL_MS = 10 * 60 * 1000;
const MAX_ITEMS = 50;

const GLYPHS =
  '가나다라마바사아자차카타파하뉴스속보정치경제사회세계국제문화과학기술스포츠현장단독분석오늘내일한국서울정부국회시장산업외교기후';

// Matches MatrixRainDepthLayer in MatrixGlyphSet.swift.
const LAYERS = [
  { columnWidth: 31, rowHeight: 29, fontSize: 12, speed: 0.58, tailLength: 13, baseOpacity: 0.20, headOpacity: 0.52 },
  { columnWidth: 24, rowHeight: 25, fontSize: 15, speed: 0.92, tailLength: 18, baseOpacity: 0.34, headOpacity: 0.78 },
  { columnWidth: 18, rowHeight: 22, fontSize: 19, speed: 1.34, tailLength: 24, baseOpacity: 0.50, headOpacity: 0.88 },
];

const FONT_STACK =
  '"SF Mono", ui-monospace, Menlo, Consolas, "Apple SD Gothic Neo", "Nanum Gothic Coding", "Malgun Gothic", monospace';

// Mirrors playbackConfiguration in TypewriterNewsView at scrollSpeed=3.5.
const SPEED = 3.5;
const TYPEWRITER = {
  titleCPS: Math.max(2, SPEED * 2.1),
  summaryCPS: Math.max(4, SPEED * 3.7),
  titlePause: Math.max(0.85, 2.8 / SPEED),
  summaryPause: Math.max(2.6, 9.0 / SPEED),
};

const params = new URLSearchParams(location.search);
const DATA_URL = params.get('data') || DATA_URL_DEFAULT;

const canvas = document.getElementById('rain');
const ctx = canvas.getContext('2d', { alpha: false });

const titleText = document.getElementById('title-text');
const titleCursor = document.getElementById('title-cursor');
const summaryText = document.getElementById('summary-text');
const summaryCursor = document.getElementById('summary-cursor');
const metaSource = document.getElementById('meta-source');
const metaTime = document.getElementById('meta-time');
const metaPosition = document.getElementById('meta-position');
const statusEl = document.getElementById('status');
const sourceLink = document.getElementById('source-link');

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

let dpr = 1;
let cssW = 0;
let cssH = 0;
let columnsByLayer = [];
let items = [];
let startTime = performance.now() / 1000;
let lastDataLoad = 0;
let dataLoadInFlight = false;
let lastItemId = null;

// --- Sizing ----------------------------------------------------------------

function resize() {
  dpr = Math.min(window.devicePixelRatio || 1, 2);
  cssW = window.innerWidth;
  cssH = window.innerHeight;
  canvas.width = Math.floor(cssW * dpr);
  canvas.height = Math.floor(cssH * dpr);
  canvas.style.width = cssW + 'px';
  canvas.style.height = cssH + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  rebuildColumns();
  if (reduceMotion) drawRain(0);
}

function hash2(a, b) {
  let h = (a * 73856093) ^ (b * 19349663);
  h ^= h >>> 13;
  return Math.abs(h | 0);
}

function rebuildColumns() {
  columnsByLayer = LAYERS.map((layer) => {
    const cols = Math.ceil(cssW / layer.columnWidth) + 1;
    return Array.from({ length: cols }, (_, c) => ({
      speedMul: 0.78 + (hash2(c, 271) % 10000) / 10000 * 0.55,
      rowOffset: (hash2(c, 9931) % 10000) / 10000,
    }));
  });
}

// --- Rain rendering --------------------------------------------------------

function drawRain(timeSec) {
  ctx.fillStyle = '#000503';
  ctx.fillRect(0, 0, cssW, cssH);

  const grad = ctx.createLinearGradient(0, 0, 0, cssH);
  grad.addColorStop(0, 'rgba(0, 0, 0, 0.72)');
  grad.addColorStop(0.5, 'rgba(0, 20, 6, 0.40)');
  grad.addColorStop(1, 'rgba(0, 0, 0, 0.86)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, cssW, cssH);

  ctx.textBaseline = 'middle';
  ctx.textAlign = 'center';

  for (let li = 0; li < LAYERS.length; li++) {
    drawLayer(LAYERS[li], columnsByLayer[li], timeSec);
  }

  drawVignette();
}

function drawLayer(layer, cols, timeSec) {
  const rows = Math.ceil(cssH / layer.rowHeight) + 4;
  const totalRows = rows + layer.tailLength;

  // Pre-compute per-column head row, so we iterate distance-major
  // (batches fillStyle/font swaps for performance).
  const headFloats = new Float32Array(cols.length);
  for (let c = 0; c < cols.length; c++) {
    const col = cols[c];
    let h = timeSec * layer.speed * col.speedMul + col.rowOffset * totalRows;
    h = ((h % totalRows) + totalRows) % totalRows;
    headFloats[c] = h - layer.tailLength; // start above the screen
  }

  for (let d = 0; d < layer.tailLength; d++) {
    const alpha = opacityFor(d, layer);
    if (alpha < 0.027) continue;

    const isHead = d === 0;
    const fontSize = isHead ? layer.fontSize * 1.08 : layer.fontSize;
    ctx.font = `${isHead ? 700 : 400} ${fontSize}px ${FONT_STACK}`;

    const [r, g, b] = colorFor(d);
    ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;

    for (let c = 0; c < cols.length; c++) {
      const rowFloat = headFloats[c] - d;
      const y = rowFloat * layer.rowHeight + layer.rowHeight * 0.5;
      if (y < -layer.rowHeight || y > cssH + layer.rowHeight) continue;

      const x = c * layer.columnWidth + layer.columnWidth * 0.5;
      const row = Math.floor(rowFloat);
      const glyph = pickGlyph(c, row, timeSec);
      ctx.fillText(glyph, x, y);
    }
  }
}

function opacityFor(distance, layer) {
  if (distance === 0) return layer.headOpacity;
  if (distance > layer.tailLength) return 0;
  const progress = distance / layer.tailLength;
  return Math.max(0.03, layer.baseOpacity * Math.pow(1 - progress, 2.35));
}

function colorFor(distance) {
  if (distance === 0) return [232, 255, 209];
  if (distance <= 3) return [148, 255, 122];
  return [20, 230, 56];
}

function pickGlyph(col, row, timeSec) {
  // Each cell holds a glyph for ~0.6s before swapping; offset by cell so swaps stagger.
  const swapBucket = Math.floor(timeSec * 1.6 + ((col * 13 + row * 7) % 5));
  const idx = hash2(col * 131 + row, swapBucket * 911) % GLYPHS.length;
  return GLYPHS[idx];
}

function drawVignette() {
  const r0 = Math.min(cssW, cssH) * 0.20;
  const r1 = Math.max(cssW, cssH) * 0.72;
  const cx = cssW * 0.5;
  const cy = cssH * 0.46;
  const grad = ctx.createRadialGradient(cx, cy, r0, cx, cy, r1);
  grad.addColorStop(0, 'rgba(0,0,0,0)');
  grad.addColorStop(1, 'rgba(0,0,0,0.58)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, cssW, cssH);
}

// --- Typewriter ------------------------------------------------------------

function computeFrame(t) {
  if (!items.length) return null;
  const durations = items.map(itemDuration);
  const total = durations.reduce((a, b) => a + b, 0);
  if (total <= 0) return null;

  let local = ((t % total) + total) % total;
  for (let i = 0; i < items.length; i++) {
    if (local < durations[i] || i === items.length - 1) {
      return frameAt(items[i], i, items.length, local);
    }
    local -= durations[i];
  }
  return frameAt(items[0], 0, items.length, 0);
}

function itemDuration(item) {
  const title = item.title || '';
  const summary = summaryFor(item);
  return (
    title.length / TYPEWRITER.titleCPS +
    TYPEWRITER.titlePause +
    summary.length / TYPEWRITER.summaryCPS +
    TYPEWRITER.summaryPause
  );
}

function summaryFor(item) {
  const s = (item.summary || '').trim();
  return s.length ? s : item.url || '';
}

function frameAt(item, index, total, local) {
  const title = item.title || '';
  const summary = summaryFor(item);
  const titleDur = title.length / TYPEWRITER.titleCPS;
  const summaryDur = summary.length / TYPEWRITER.summaryCPS;

  let revealedTitle, revealedSummary, cursorTarget;
  if (local < titleDur) {
    revealedTitle = title.slice(0, Math.floor(local * TYPEWRITER.titleCPS));
    revealedSummary = '';
    cursorTarget = 'title';
  } else if (local < titleDur + TYPEWRITER.titlePause) {
    revealedTitle = title;
    revealedSummary = '';
    cursorTarget = 'title';
  } else if (local < titleDur + TYPEWRITER.titlePause + summaryDur) {
    const sLocal = local - titleDur - TYPEWRITER.titlePause;
    revealedTitle = title;
    revealedSummary = summary.slice(0, Math.floor(sLocal * TYPEWRITER.summaryCPS));
    cursorTarget = 'summary';
  } else {
    revealedTitle = title;
    revealedSummary = summary;
    cursorTarget = 'summary';
  }

  return { item, index, total, revealedTitle, revealedSummary, cursorTarget };
}

// --- Overlay update --------------------------------------------------------

function updateOverlay(frame) {
  if (!frame) return;
  if (frame.item.id !== lastItemId) {
    lastItemId = frame.item.id;
    metaSource.textContent = frame.item.sourceName || '';
    metaTime.textContent = formatTime(frame.item.publishedAt);
    sourceLink.href = frame.item.url || '#';
    sourceLink.hidden = !frame.item.url;
  }
  metaPosition.textContent = `${frame.index + 1}/${frame.total}`;
  titleText.textContent = frame.revealedTitle;
  summaryText.textContent = frame.revealedSummary;
  titleCursor.hidden = frame.cursorTarget !== 'title';
  summaryCursor.hidden = frame.cursorTarget !== 'summary';
}

function formatTime(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
}

// --- Data ------------------------------------------------------------------

async function loadData(showStatusOnFailure) {
  if (dataLoadInFlight) return;
  dataLoadInFlight = true;
  try {
    const url = DATA_URL + (DATA_URL.includes('?') ? '&' : '?') + '_=' + Date.now();
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const json = await res.json();
    const list = Array.isArray(json.items) ? json.items.slice() : [];
    list.sort((a, b) => {
      const ta = a.publishedAt || '';
      const tb = b.publishedAt || '';
      if (ta !== tb) return tb.localeCompare(ta);
      return (a.title || '').localeCompare(b.title || '');
    });
    const next = list.slice(0, MAX_ITEMS);
    const changed = next.length !== items.length ||
      next.some((it, i) => it.id !== items[i]?.id);
    items = next;
    if (changed) {
      startTime = performance.now() / 1000;
      lastItemId = null;
    }
    if (items.length) {
      statusEl.hidden = true;
    } else if (showStatusOnFailure) {
      statusEl.hidden = false;
      statusEl.textContent = '뉴스가 없습니다.';
    }
    lastDataLoad = Date.now();
  } catch (e) {
    if (showStatusOnFailure) {
      statusEl.hidden = false;
      statusEl.textContent = '뉴스를 불러오지 못했습니다.';
    }
    console.warn('matrix-news: data load failed', e);
  } finally {
    dataLoadInFlight = false;
  }
}

// --- Main loop -------------------------------------------------------------

function tick(nowMs) {
  const now = nowMs / 1000;
  const t = now - startTime;
  if (!reduceMotion) drawRain(now);

  const frame = computeFrame(t);
  updateOverlay(frame);

  if (Date.now() - lastDataLoad > REFRESH_INTERVAL_MS) {
    lastDataLoad = Date.now();
    loadData(false);
  }

  requestAnimationFrame(tick);
}

window.addEventListener('resize', resize);
resize();
statusEl.hidden = false;
loadData(true).then(() => {
  requestAnimationFrame(tick);
});
