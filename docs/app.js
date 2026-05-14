// Matrix News — web MVP.
// Fetches latest.json from the same repo and renders Korean Matrix rain
// with a typewriter headline overlay. Visual params mirror the SwiftUI app.

const DATA_URL_DEFAULT =
  'https://raw.githubusercontent.com/pathcosmos/matrix-news-on-mac/main/Data/latest.json';
const REFRESH_INTERVAL_MS = 10 * 60 * 1000;
const MAX_ITEMS = 50;

const GLYPHS =
  '가나다라마바사아자차카타파하뉴스속보정치경제사회세계국제문화과학기술스포츠현장단독분석오늘내일한국서울정부국회시장산업외교기후';

// Matches MatrixRainDepthLayer + MatrixRainLayerRenderPlan in the SwiftUI app.
// tailStep: draw every Nth glyph in the tail so the stream reads as a chain of
// drops rather than a packed grid. headGlow: extra blurred pass under the head.
// seedKey: stable per-layer seed so motion parameters differ between layers.
const LAYERS = [
  { columnWidth: 31, rowHeight: 29, fontSize: 12, speed: 0.58, tailLength: 13, tailStep: 3, baseOpacity: 0.20, headOpacity: 0.52, headGlowOpacity: 0,    headGlowRadius: 0,   seedKey: 11 },
  { columnWidth: 24, rowHeight: 25, fontSize: 15, speed: 0.92, tailLength: 18, tailStep: 3, baseOpacity: 0.34, headOpacity: 0.78, headGlowOpacity: 0.18, headGlowRadius: 2.4, seedKey: 23 },
  { columnWidth: 18, rowHeight: 22, fontSize: 19, speed: 1.34, tailLength: 24, tailStep: 2, baseOpacity: 0.50, headOpacity: 0.88, headGlowOpacity: 0.29, headGlowRadius: 4.4, seedKey: 37 },
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
  // Mirrors MatrixRainColumnMotion(column:layer:) in the SwiftUI app:
  // each column gets its own speed multiplier, phase offset, cycle gap, and
  // gentle horizontal drift so the rain looks layered instead of synchronized.
  columnsByLayer = LAYERS.map((layer) => {
    const cols = Math.ceil(cssW / layer.columnWidth) + 3;
    return Array.from({ length: cols }, (_, c) => {
      const seed = hash2(c, layer.seedKey);
      return {
        speedRowsPerSecond: layer.speed * (5.8 + (seed % 23) / 15.0),
        phaseRows: (seed % 10000) / 10000 * 80,
        gapRows: 5 + (seed % Math.max(6, layer.tailLength)),
        driftPhase: ((seed >>> 3) % 6283) / 1000,
        driftRate: 0.08 + ((seed >>> 6) % 19) / 220,
        driftMagnitude: 0.08 + ((seed >>> 9) % 17) / 210,
      };
    });
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
  const baseRows = Math.ceil(cssH / layer.rowHeight) + layer.tailLength + 5;

  // Per-column head progress. SwiftUI uses positive remainder over (rows + gapRows)
  // so each stream has an empty pause between cycles.
  const headProgress = new Float64Array(cols.length);
  const cycleRows = new Int32Array(cols.length);
  const xOffsets = new Float64Array(cols.length);
  for (let c = 0; c < cols.length; c++) {
    const col = cols[c];
    const cycle = baseRows + col.gapRows;
    cycleRows[c] = cycle;
    let p = (col.phaseRows + timeSec * col.speedRowsPerSecond) % cycle;
    if (p < 0) p += cycle;
    headProgress[c] = p;
    xOffsets[c] = Math.sin(timeSec * col.driftRate + col.driftPhase) * col.driftMagnitude * layer.columnWidth;
  }

  // Sparse tail distances: 0 (head), then every tailStep up to tailLength.
  const distances = [];
  for (let d = 0; d <= layer.tailLength; d += layer.tailStep) distances.push(d);

  // Tail pass (distance-major to batch fillStyle/font swaps).
  for (const d of distances) {
    const alpha = opacityFor(d, layer);
    if (alpha < 0.027) continue;
    const isHead = d === 0;
    const fontSize = isHead ? layer.fontSize * 1.08 : layer.fontSize;
    ctx.font = `${isHead ? 700 : 400} ${fontSize}px ${FONT_STACK}`;
    const [r, g, b] = colorFor(d);
    ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;

    for (let c = 0; c < cols.length; c++) {
      const progress = headProgress[c];
      // SwiftUI yPosition: (progress + (distance - tailLength)) * rowHeight.
      const rowFloat = progress + d - layer.tailLength;
      const y = rowFloat * layer.rowHeight + layer.rowHeight * 0.5;
      if (y < -layer.rowHeight * 2 || y > cssH + layer.rowHeight * 2) continue;

      const x = c * layer.columnWidth + layer.columnWidth * 0.5 + xOffsets[c];
      const cycle = cycleRows[c];
      const rowIdx = ((Math.floor(progress) + d) % cycle + cycle) % cycle;
      drawGlyph(pickGlyph(c, rowIdx, timeSec), x, y, orientationFor(c, rowIdx));
    }
  }

  // Head glow pass — draw a blurred halo under each head glyph.
  if (layer.headGlowOpacity > 0) {
    ctx.font = `700 ${layer.fontSize * 1.08}px ${FONT_STACK}`;
    ctx.fillStyle = `rgba(184, 255, 158, ${layer.headGlowOpacity})`;
    ctx.shadowColor = `rgba(184, 255, 158, ${Math.min(0.85, layer.headGlowOpacity * 2.2)})`;
    ctx.shadowBlur = layer.headGlowRadius * 2.4;
    for (let c = 0; c < cols.length; c++) {
      const progress = headProgress[c];
      const rowFloat = progress - layer.tailLength;
      const y = rowFloat * layer.rowHeight + layer.rowHeight * 0.5;
      if (y < -layer.rowHeight * 2 || y > cssH + layer.rowHeight * 2) continue;
      const x = c * layer.columnWidth + layer.columnWidth * 0.5 + xOffsets[c];
      const cycle = cycleRows[c];
      const rowIdx = (Math.floor(progress) % cycle + cycle) % cycle;
      drawGlyph(pickGlyph(c, rowIdx, timeSec), x, y, orientationFor(c, rowIdx));
    }
    ctx.shadowBlur = 0;
    ctx.shadowColor = 'rgba(0,0,0,0)';
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
  // Matches MatrixRainGlyphComposer: glyph is hashed from (column, row, tick),
  // where tick advances twice per second so glyphs flicker even within a row.
  const tick = Math.floor(timeSec * 2);
  let h = (col * 73856093) ^ (row * 19349663) ^ (tick * 83492791);
  h ^= h >>> 13;
  return GLYPHS[Math.abs(h | 0) % GLYPHS.length];
}

// Matches MatrixGlyphOrientation.orientation(column:row:): ~0.1% of cells
// render upside down, ~3.4% horizontally mirrored, the rest normal.
function orientationFor(col, row) {
  let v = (col * 73856093) ^ (row * 19349663);
  v ^= v >>> 13;
  v = Math.abs(v | 0);
  if (v % 997 === 0) return 2; // upside down
  if (v % 29 === 0) return 1;  // mirrored
  return 0;
}

function drawGlyph(glyph, x, y, orient) {
  if (orient === 0) {
    ctx.fillText(glyph, x, y);
    return;
  }
  ctx.save();
  ctx.translate(x, y);
  if (orient === 1) ctx.scale(-1, 1);
  else ctx.scale(1, -1);
  ctx.fillText(glyph, 0, 0);
  ctx.restore();
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
