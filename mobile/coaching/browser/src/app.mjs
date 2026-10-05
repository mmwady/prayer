import { RecognizerClient } from './client.mjs';
import { ARABIC, CLASSES, SCHEMA_VERSION, StableCapture, readSession, saveSession, validResult } from './core.mjs';
import { canvasFor } from './image.mjs';
import { temporal, sequenceReport } from './sequence.mjs';
const $ = id => document.getElementById(id), client = new RecognizerClient();
let info, stream, live = false, stopped = false, timer, generation = 0, activeInference, captures = [], samples = [], recent = [], stable = new StableCapture();
const status = text => { $('status').textContent = text; };
const warning = text => { $('diagnostic').textContent = text; $('diagnostic').className = text ? 'warning' : ''; };
const label = code => code?.replace(/^\d_/, '').replaceAll('_', ' ') ?? 'غير متاح';
const arabic = code => ARABIC[CLASSES.indexOf(code)] ?? 'لا توجد وضعية قابلة للتصنيف';
const percent = x => (x * 100).toFixed(1) + '%';
function node(tag, text, className) { const n = document.createElement(tag); if (text !== undefined) n.textContent = text; if (className) n.className = className; return n; }
function models(result) {
  const cards = node('div', undefined, 'models');
  if (result.individual_models?.length !== 3) { cards.append(node('p', 'تحذير تشخيصي: قرارات النماذج الثلاثة غير متاحة. أعد تحميل النماذج.', 'warning')); return cards; }
  for (const m of result.individual_models) {
    const card = node('article', undefined, 'model');
    card.append(node('small', 'Model seed ' + m.seed), node('h3', label(m.predicted_action)), node('p', arabic(m.predicted_action), 'arabic'), node('strong', percent(m.confidence)));
    card.append(node('p', m.available === false ? 'غير متاح — لا توجد وضعية صالحة' : m.class_index === result.class_index ? 'يتفق مع القرار المجمع' : 'يختلف عن القرار المجمع — عدم يقين', m.class_index !== result.class_index ? 'warning' : 'ok'));
    cards.append(card);
  }
  return cards;
}
function resultNode(result, compact = false) {
  const panel = node('article', undefined, compact ? '' : 'result');
  panel.append(node('small', 'القرار المجمع · Ensemble'), node('h2', label(result.predicted_action)), node('p', arabic(result.predicted_action), 'arabic'), node('div', 'ثقة التصنيف ' + percent(result.confidence), 'confidence'));
  if (compact) { const d = node('details'); d.append(node('summary', 'قرارات النماذج الثلاثة'), models(result)); panel.append(d); }
  else panel.append(models(result)); // Directly beneath aggregate confidence.
  if (result.classifier_disagreement) panel.append(node('p', 'تختلف قرارات المصنفات. راجع جميع النتائج؛ ثقة التصنيف لا تقيس صحة الصلاة.', 'warning'));
  if (result.warning) panel.append(node('p', result.warning, 'warning'));
  panel.append(node('p', `وضوح الجسم: ${result.mean_visibility?.toFixed(3) ?? '—'} · الاستعادة: ${result.recovery_method} · ${result.inference_ms.toFixed(0)} ms`, 'metadata'));
  if (!compact) {
    const top = node('div', undefined, 'top');
    for (const item of result.top3) { top.append(node('span', `${arabic(item.action)} · ${label(item.action)} · ${percent(item.probability)}`)); const progress = node('progress'); progress.max = 1; progress.value = item.probability; top.append(progress); }
    panel.append(top);
  }
  return panel;
}
function showCaptures() {
  $('captures').replaceChildren();
  for (const capture of captures) {
    const card = node('article', undefined, 'capture');
    if (capture.image) { const img = node('img'); img.src = capture.image; img.alt = 'وضعية مرصودة على جهازك'; card.append(img); }
    card.append(node('small', capture.time), resultNode(capture.result, true)); $('captures').append(card);
  }
}
function persist(result) {
  recent = [result, ...recent].slice(0, 12);
  try { saveSession(sessionStorage, info.model_version, recent); } catch (e) { warning('تعذر حفظ الجلسة المحلية: ' + e.message); }
}
function preview(value) {
  const prepared = canvasFor(value.preview), ctx = $('preview').getContext('2d');
  ctx.drawImage(prepared, 0, 0); $('preview').hidden = false;
  const points = value.landmarks;
  ctx.strokeStyle = '#2be5a3'; ctx.fillStyle = '#ffbe3b'; ctx.lineWidth = 3;
  for (const [a, b] of [[11,12],[11,13],[13,15],[12,14],[14,16],[11,23],[12,24],[23,24],[23,25],[25,27],[24,26],[26,28],[27,29],[29,31],[28,30],[30,32]]) {
    if ((points[a]?.visibility ?? 0) >= .2 && (points[b]?.visibility ?? 0) >= .2) { ctx.beginPath(); ctx.moveTo(points[a].x * 384, points[a].y * 512); ctx.lineTo(points[b].x * 384, points[b].y * 512); ctx.stroke(); }
  }
  for (const p of points) if ((p.visibility ?? 0) >= .2) { ctx.beginPath(); ctx.arc(p.x * 384, p.y * 512, 3, 0, 2 * Math.PI); ctx.fill(); }
}
async function analyze(source, auto = false, token = generation) {
  if (!info || client.busy) return;
  try {
    status('جارٍ التحليل على جهازك…');
    activeInference = client.analyze(source);
    const value = await activeInference;
    if (token !== generation || stopped) return;
    if (!validResult(value.result, info.model_version)) throw Error('Prediction schema mismatch; clear the old application cache');
    $('result').replaceChildren(resultNode(value.result)); preview(value); persist(value.result);
    const now = performance.now();
    samples.push({ timestamp_ms: Math.round(now), result: value.result });
    if (samples.length > 10000) { live = false; warning('بلغت الجلسة حد 10000 عينة. راجع التقرير وابدأ جلسة جديدة.'); }
    if (!auto || stable.update(value.result, now / 1000)) {
      captures.unshift({ result: value.result, image: $('preview').toDataURL('image/jpeg', .9), time: new Date().toLocaleTimeString('ar-EG') }); captures = captures.slice(0, 12); showCaptures();
    }
    status(`تم التحليل محليًا · ${info.mode === 'worker' ? 'Web Worker / WASM' : 'WASM مع مسار التوافق'}`);
    return value.result.inference_ms;
  } catch (e) { live = false; warning(e.message); status('تعذر التحليل المحلي.'); }
  finally { activeInference = null; }
}
function stopCamera() {
  live = false; generation++; clearTimeout(timer); stream?.getTracks().forEach(t => t.stop()); stream = null;
  $('camera').srcObject = null; $('camera').hidden = true; $('snapshot').disabled = $('live').disabled = $('stop').disabled = true; $('start').disabled = false; $('live').textContent = 'ابدأ التعرف المباشر';
}
async function tick(token) {
  if (!live || !stream || token !== generation) return;
  const ms = await analyze($('camera'), true, token);
  // Inference completes before scheduling the next frame: no overlap or queued stale frames.
  if (live && token === generation) timer = setTimeout(() => tick(token), Math.max(220, Math.min(2000, (ms ?? 220) * .25)));
}
for (const id of ['upload', 'photo']) $(id).onchange = async event => { const file = event.target.files[0]; if (file) { stopCamera(); stopped = false; const token = generation; await activeInference?.catch(() => {}); if (token === generation) await analyze(file, false, token); event.target.value = ''; } };
$('start').onclick = async () => {
  try { if (!isSecureContext) throw Error('الكاميرا تحتاج HTTPS أو localhost'); stopCamera(); stopped = false; const token = generation; const opened = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false }); if (stopped || token !== generation) { opened.getTracks().forEach(t => t.stop()); return; } stream = opened; $('camera').srcObject = stream; $('camera').hidden = false; await $('camera').play(); if (token !== generation) return; $('start').disabled = true; $('snapshot').disabled = $('live').disabled = $('stop').disabled = false; status('الكاميرا جاهزة — المعالجة على جهازك فقط'); }
  catch (e) { warning('تعذر فتح الكاميرا: ' + e.message); }
};
$('snapshot').onclick = () => analyze($('camera'));
$('live').onclick = () => { live = !live; clearTimeout(timer); $('live').textContent = live ? 'أوقف التعرف المباشر' : 'ابدأ التعرف المباشر'; if (live) { stable = new StableCapture(Number($('threshold').value) / 100); tick(generation); } };
$('stop').onclick = stopCamera;
$('threshold').oninput = () => { stable.threshold = Number($('threshold').value) / 100; $('threshold-value').textContent = $('threshold').value + '%'; };
$('clear').onclick = () => { generation++; live = false; clearTimeout(timer); captures = []; samples = []; recent = []; stable = new StableCapture(Number($('threshold').value) / 100); try { sessionStorage.removeItem('iqtadi-recognizer-session'); } catch { /* Storage may be disabled. */ } $('result').replaceChildren(); $('sequence').replaceChildren(); $('preview').hidden = true; showCaptures(); $('live').textContent = 'ابدأ التعرف المباشر'; };
$('report').onclick = () => {
  const report = sequenceReport($('prayer').value, temporal(samples)); $('sequence').replaceChildren(node('p', report.notice), node('h3', report.overall_result === 'OBSERVED_COMPLETE' ? 'رُصد تسلسل الحركات كاملًا' : 'تحتاج النتائج إلى مراجعة'));
  for (const row of report.rakahs) { const details = node('details'); details.open = true; details.append(node('summary', 'الركعة ' + row.rakah_number)); for (const s of row.stations) details.append(node('div', s.arabic_label + ' · ' + (s.status === 'DETECTED' ? 'مرصود' : 'غير مؤكد'), 'station')); $('sequence').append(details); }
  $('sequence').append(node('p', `حركات إضافية أو ملتبسة: ${report.unexpected_movements.length}`));
};
$('download').onclick = () => { const url = URL.createObjectURL(new Blob([JSON.stringify({ schema_version: SCHEMA_VERSION, model_version: info?.model_version, results: recent, report: sequenceReport($('prayer').value, temporal(samples)) }, null, 2)], { type: 'application/json' })); const a = node('a'); a.href = url; a.download = 'iqtadi-local-results.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); };
document.addEventListener('visibilitychange', () => { if (document.hidden) stopCamera(); });
addEventListener('pagehide', () => { stopped = true; stopCamera(); client.close(); });
try {
  info = await client.initialize(); try { recent = readSession(sessionStorage, info.model_version); } catch { recent = []; } captures = recent.map(result => ({ result, time: 'نتيجة محلية محفوظة؛ الصورة غير مخزنة' })); showCaptures();
  if (recent[0]) $('result').replaceChildren(resultNode(recent[0]));
  status('النماذج المحلية جاهزة — اختر صورة أو افتح الكاميرا');
  for (const id of ['upload', 'photo', 'start']) $(id).disabled = false;
  if (info.fallback_reason) warning('مسار التوافق المحلي نشط: ' + info.fallback_reason + '. قد تكون المعالجة أبطأ.');
} catch (e) { warning(e.message); status('تعذر تحميل النماذج. تحقق من ملفات التطبيق؛ الصور لا تزال على جهازك.'); }
