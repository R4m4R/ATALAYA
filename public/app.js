/* ---- Iconos de la pestaña: buscador normal, advertencia parpadeante, informacion ---- */
const svgUri = s => 'data:image/svg+xml,' + encodeURIComponent(s);
// Icono normal de la pestaña: el faro con radar de la cabecera (haces a izquierda y derecha)
const ICON_SEARCH = svgUri("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M12 5 L20.5 1.5 A9 9 0 0 1 20.5 8.5 Z' fill='#4a6d8c' opacity='.35'/><path d='M12 5 L3.5 1.5 A9 9 0 0 0 3.5 8.5 Z' fill='#4a6d8c' opacity='.35'/><rect x='9' y='3' width='6' height='4' rx='1' fill='#2f4f6f'/><path d='M12 0.4 L10.3 3 H13.7 Z' fill='#2f4f6f'/><circle cx='12' cy='5' r='1.4' fill='#f4c542'/><path d='M10 7 L8.4 20 H15.6 L14 7 Z' fill='#fff' stroke='#2f4f6f' stroke-width='1.5' stroke-linejoin='round'/><path d='M10.6 11.5 H13.4 M10.2 15.5 H13.8' stroke='#4a6d8c' stroke-width='1'/><path d='M6.5 21 H17.5' stroke='#2f4f6f' stroke-width='2' stroke-linecap='round'/></svg>");
const ICON_WARN   = svgUri("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M12 2L23 21H1Z' fill='#d4621f' stroke='#8a2e0a' stroke-width='1'/><rect x='10.8' y='8' width='2.4' height='7.5' fill='#fff'/><rect x='10.8' y='16.8' width='2.4' height='2.4' fill='#fff'/></svg>");
const ICON_INFO   = svgUri("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><circle cx='12' cy='12' r='11' fill='#3c6ea8'/><rect x='10.8' y='10' width='2.4' height='8' fill='#fff'/><circle cx='12' cy='6.8' r='1.6' fill='#fff'/></svg>");
const SEEN_KEY = 'vigia_noticias_vistas';
let ALARM_DOWN = false, ALARM_NEWS = false, PREV_DOWN = new Set(), PENDING = [], blinkTimer = null;

const LEVELS = [
  {key:'Critica', label:'Crítica', color:'var(--crit)'},
  {key:'Grave',   label:'Grave',   color:'var(--grave)'},
  {key:'Media',   label:'Media',   color:'var(--media)'},
  {key:'Baja',    label:'Baja',    color:'var(--baja)'},
  {key:'Info',    label:'Info',    color:'var(--info)'}
];
const RANK = {Critica:4, Grave:3, Media:2, Baja:1, Info:0};
const LABEL = Object.fromEntries(LEVELS.map(l => [l.key, l.label]));
let DATA = null;
let SETTINGS = null;
let ACTIVE_SEVS = ['Critica','Grave'];
let PROGRESS_PCT = 0;
let PROGRESS_TIMER = null;
let PROGRESS_MSG = '';
let PROGRESS_STAMP_MSG = '';

const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function startProgress(msg, stampMsg){
  PROGRESS_PCT = 0;
  PROGRESS_MSG = msg;
  PROGRESS_STAMP_MSG = stampMsg || msg;
  clearInterval(PROGRESS_TIMER);
  PROGRESS_TIMER = setInterval(() => {
    if(PROGRESS_PCT < 90) PROGRESS_PCT += Math.random() * 8 + 3;
    updateProgressDisplay();
  }, 500);
}

function stopProgress(){
  PROGRESS_PCT = 100;
  updateProgressDisplay();
  clearInterval(PROGRESS_TIMER);
  PROGRESS_TIMER = null;
}

function updateProgressDisplay(){
  const msgEl = $('feed').querySelector('.loading span');
  if(msgEl){
    msgEl.textContent = PROGRESS_MSG + ' ' + Math.round(PROGRESS_PCT) + '%';
  }
  const stamp = $('stamp');
  if(stamp && PROGRESS_STAMP_MSG){
    stamp.textContent = PROGRESS_STAMP_MSG + ' ' + Math.round(PROGRESS_PCT) + '%';
  }
}

function setBusy(on){
  $('scanIcon').classList.toggle('busy', on);
  $('live').classList.toggle('busy', on);
  $('btnRefresh').disabled = on;
  $('refIco').classList.toggle('spin', on);
  $('stamp').textContent = on ? 'Buscando en las fuentes...' : (DATA ? 'Actualizado ' + DATA.generated : 'Sin datos');
}

// Consulta el progreso REAL del refresco de fuentes (worker en 2o plano) hasta que termine.
// El % mostrado es fuentes_completadas / fuentes_totales, no un valor inventado.
function waitForFuentes(totalFallback){
  return new Promise(resolve => {
    const tick = async () => {
      try{
        const r = await fetch('/api/progreso_fuentes');
        if(r.ok){
          const p = await r.json();
          const total = p.total || totalFallback || 0;
          PROGRESS_PCT = total > 0 ? Math.min(99, Math.round((p.done / total) * 100)) : 0;
          updateProgressDisplay();
          if(!p.activo){ resolve(); return; }
        }
      }catch(e){}
      setTimeout(tick, 400);
    };
    tick();
  });
}

async function load(force){
  setBusy(true);
  $('feed').innerHTML = `<div class="loading">
      <svg class="radar" viewBox="0 0 64 64" aria-hidden="true">
        <circle cx="32" cy="32" r="28" fill="#f5f7fa" stroke="#c9d1dc"/>
        <circle cx="32" cy="32" r="18" fill="none" stroke="#c9d1dc"/>
        <circle cx="32" cy="32" r="8" fill="none" stroke="#c9d1dc"/>
        <g class="sweep"><path d="M32 32 L32 4 A28 28 0 0 1 52 12 Z" fill="#4a6d8c" opacity=".35"/>
        <line x1="32" y1="32" x2="32" y2="4" stroke="#2f4f6f" stroke-width="2"/></g>
        <circle class="blip" cx="44" cy="22" r="3" fill="#b3261e"/>
        <circle class="blip" cx="22" cy="40" r="2.5" fill="#d4621f" style="animation-delay:.5s"/>
      </svg>
      <span>Buscando noticias en las fuentes configuradas...</span></div>`;
  clearInterval(PROGRESS_TIMER);
  PROGRESS_PCT = 0;
  PROGRESS_MSG = 'Buscando noticias en las fuentes configuradas...';
  PROGRESS_STAMP_MSG = 'Buscando en las fuentes...';
  updateProgressDisplay();
  try{
    // Reintenta mientras el servidor arranca (evita tener que recargar la pagina)
    let r = null;
    for(let i = 0; i < 15 && !r; i++){
      try { r = await fetch('/api/news' + (force ? '?refresh=1' : '')); }
      catch(err){ if(i === 14) throw err; await new Promise(res => setTimeout(res, 1000)); }
    }
    if(!r.ok) throw new Error('HTTP ' + r.status);
    let body = await r.json();

    if(body && body.iniciando){
      // El refresco corre en segundo plano: se sigue el progreso real hasta que termine
      await waitForFuentes(body.total || 0);
      r = await fetch('/api/news');
      if(!r.ok) throw new Error('HTTP ' + r.status);
      body = await r.json();
    }

    DATA = body;
    PROGRESS_PCT = 100;
    updateProgressDisplay();
    render();
    checkNews();
  }catch(e){
    $('feed').innerHTML = '<div class="empty">No se pudo cargar el panel (' + esc(e.message) + '). Revisa que server.ps1 este en marcha.</div>';
    clearInterval(PROGRESS_TIMER);
  }finally{
    setBusy(false);
  }
}

function render(){
  const d = DATA;
  ACTIVE_SEVS = d.severities || ACTIVE_SEVS;
  $('days').textContent = d.windowDays;
  const items = d.items || [];
  const count = s => items.filter(i => i.severity === s).length;
  $('kTotal').textContent = d.total;
  $('kCrit').textContent = count('Critica');
  const crit = count('Critica');
  $('critBadge').textContent = crit;
  $('critBadge').classList.toggle('zero', crit === 0);
  // Contar emergencias (críticas con CVSS >= umbral configurable)
  const emerg = items.filter(i => i.severity === 'Critica' && i.cvss && parseFloat(i.cvss) >= UI.emergCVSS).length;
  $('kEmerg').textContent = emerg;
  $('kEmergTile').style.display = emerg > 0 ? 'flex' : 'none';
  $('kGrave').textContent = count('Grave');
  $('kMedia').textContent = count('Media');
  $('kBaja').textContent = count('Baja');
  $('kInfo').textContent = count('Info');
  $('kSrc').textContent = d.sources.filter(s => s.ok).length + '/' + d.sources.length;
  // Fuentes: verde si todas responden, naranja si falla alguna, rojo si fallan 3 o mas
  const failN = d.sources.length - d.sources.filter(s => s.ok).length;
  $('kSrcTile').className = 'kpi ' + (failN === 0 ? 'sok' : (failN >= 3 ? 'sbad' : 'swarn'));
  // Las etiquetas de severidad solo aparecen si ese nivel esta seleccionado
  ['Critica','Grave','Media','Baja','Info'].forEach(k => {
    const el = document.querySelector(`[data-kpi="${k}"]`);
    if(el) el.classList.toggle('hidden', !ACTIVE_SEVS.includes(k));
  });

  renderToggles();

  const srcSel = $('fSrc'), tpSel = $('fTopic');
  const curSrc = srcSel.value, curTp = tpSel.value;
  const srcs = [...new Set(d.sources.map(s => s.name))];
  srcSel.innerHTML = '<option value="">Todas las fuentes</option>' + srcs.map(s => `<option>${esc(s)}</option>`).join('');
  tpSel.innerHTML = '<option value="">Todos los temas</option>' + (d.topics||[]).map(t => `<option>${esc(t)}</option>`).join('');
  srcSel.value = curSrc; tpSel.value = curTp;

  renderFeed();
  renderTopics();
  $('sources').innerHTML = d.sources.map(s => `
    <tr class="clickable" data-src="${esc(s.name)}" title="Filtrar por esta fuente">
      <td><a href="${esc(s.url)}" target="_blank" rel="noopener" style="color:var(--txt)" onclick="event.stopPropagation()">${esc(s.name)}</a></td>
      <td><span class="dot" style="background:${s.ok ? '#2e8b57' : 'var(--crit)'}"></span>${s.ok ? 'OK' : esc(s.error || 'Error')}</td>
      <td>${s.total}</td></tr>`).join('');
}

function renderToggles(){
  // Todos los niveles visibles; los activos van marcados y se pueden activar o desactivar al pulsar
  $('togs').innerHTML = LEVELS.map(l => `
    <span class="tog ${l.key} ${ACTIVE_SEVS.includes(l.key) ? 'on' : ''}" data-sev-toggle="${l.key}">
      <i style="background:${l.color}"></i>${l.label}</span>`).join('');
}

function activeFilters(){
  const f = [];
  if($('fSev').value) f.push(['sev', 'Severidad: ' + LABEL[$('fSev').value]]);
  if($('fSrc').value) f.push(['src', 'Fuente: ' + $('fSrc').value]);
  if($('fTopic').value) f.push(['topic', 'Tema: ' + $('fTopic').value]);
  const box = $('activeFilter');
  box.classList.toggle('show', f.length > 0);
  box.innerHTML = f.length ? '<span>Filtros activos:</span>' + f.map(([k,t]) =>
    `<span class="chip on" data-clear="${k}" title="Quitar filtro">${esc(t)} ✕</span>`).join('') +
    `<span class="chip" data-clear="all">Limpiar todo</span>` : '';
}

// Buscador del feed: si hay palabra, el feed muestra el resultado de la busqueda en el periodo elegido
let SEARCH = null, SEARCH_T = null, SEARCH_SEQ = 0;
function feedItems(){
  if(SEARCH) return SEARCH.items || [];
  if(!DATA) return [];
  return DATA.items || [];
}
function setSearchBusy(on){ $('scanIcon').classList.toggle('busy', on); $('sIcon').classList.toggle('busy', on); }
// Vuelve al estado por defecto: sin palabra y con el feed normal (lo que habia al principio)
function resetSearch(){
  $('gQ').value = '';
  clearTimeout(SEARCH_T);
  SEARCH = null;
  renderFeed();
}
async function runSearch(){
  const input = $('gQ').value.trim();
  if(!input){ SEARCH = null; renderFeed(); return; }

  setSearchBusy(true);
  $('feed').innerHTML = '<div class="loading"><span>Buscando en el histórico...</span></div>';
  startProgress('Buscando en el histórico...', 'Buscando...');
  const seq = ++SEARCH_SEQ;
  try{
    // Buscar SOLO en el fichero interno de noticias (nunca en las fuentes en vivo)
    const r = await fetch('/api/archivo?dias=365');
    if(!r.ok) throw new Error('HTTP ' + r.status);
    const body = await r.json();
    const archivo = body.items || [];
    if(seq !== SEARCH_SEQ) return;

    // Separar búsqueda por fecha y por palabra
    const partes = input.split(/\s+/);
    let fechaFiltro = null;
    let palabras = [];

    for(const parte of partes){
      // Detectar formato de fecha: YYYY/MM/DD, YYYY/MM o YYYY (tambien con guiones: YYYY-MM-DD)
      if(/^\d{4}[/-]\d{2}[/-]\d{2}$/.test(parte) || /^\d{4}[/-]\d{2}$/.test(parte) || /^\d{4}$/.test(parte)){
        fechaFiltro = parte.replace(/\//g, '-');
      } else {
        palabras.push(parte.toLowerCase());
      }
    }

    // Filtrar resultados
    const items = archivo.filter(h => {
      const fecha = h.date || '';
      const titulo = (h.title || '').toLowerCase();
      const cves = (h.cves || []).join(' ').toLowerCase();
      const fuentes = (h.sources || []).join(' ').toLowerCase();
      const temas = (h.topics || []).join(' ').toLowerCase();
      const contenido = titulo + ' ' + cves + ' ' + fuentes + ' ' + temas;

      // Filtro por fecha si se especificó (la fecha guardada es YYYY-MM-DD[ HH:mm])
      if(fechaFiltro && !fecha.startsWith(fechaFiltro)) return false;

      // Filtro por palabras: todas deben aparecer
      if(palabras.length > 0 && !palabras.every(palabra => contenido.includes(palabra))) return false;

      return true;
    });

    SEARCH = {items: items};
    stopProgress();
  }catch(e){
    clearInterval(PROGRESS_TIMER);
    SEARCH = {items: []};
  }finally{
    setSearchBusy(false);
  }
  renderFeed();
}
$('gQ').oninput = () => {
  if(!$('gQ').value.trim()){ resetSearch(); return; }
  clearTimeout(SEARCH_T); SEARCH_T = setTimeout(runSearch, 400);
};
$('gQ').onkeydown = e => { if(e.key === 'Enter'){ clearTimeout(SEARCH_T); runSearch(); } };
$('gQ').addEventListener('search', () => { if(!$('gQ').value.trim()) resetSearch(); });
$('btnClear').onclick = resetSearch;

// Boton "Filtros": muestra/oculta el desplegable con fuente, tema y severidad, junto al boton
$('btnFiltros').onclick = (e) => {
  e.stopPropagation();
  const dd = $('filtersDropdown');
  const btn = $('btnFiltros');
  const wasOpen = dd.classList.contains('open');
  dd.classList.toggle('open');
  if(!wasOpen){
    const wrapW = dd.offsetParent ? dd.offsetParent.clientWidth : window.innerWidth;
    let left = btn.offsetLeft + btn.offsetWidth + 8;
    if(left + dd.offsetWidth > wrapW){ left = Math.max(0, btn.offsetLeft - dd.offsetWidth - 8); }
    dd.style.left = left + 'px';
    dd.style.top = btn.offsetTop + 'px';
  }
};
document.addEventListener('click', (e) => {
  const dd = $('filtersDropdown');
  if(dd.classList.contains('open') && !dd.contains(e.target) && e.target !== $('btnFiltros')){
    dd.classList.remove('open');
  }
});

// URL de la web de cada fuente (la definida en fuentes.txt)
function srcUrl(name){
  const f = ((DATA && DATA.sources) || []).find(x => x.name === name);
  return f && f.url ? f.url : '#';
}

function renderFeed(){
  if(!DATA) return;
  const sev = $('fSev').value, src = $('fSrc').value, tp = $('fTopic').value;
  const q = '';
  const items = feedItems().filter(i =>
    (!sev || i.severity === sev) &&
    (!src || i.sources.includes(src)) &&
    (!tp  || i.topics.includes(tp)) &&
    (!q   || (i.title + ' ' + i.cves.join(' ')).toLowerCase().includes(q)));
  activeFilters();
  $('feedCount').textContent = items.length;
  $('feedTitle').textContent = 'Feed de amenazas de los ultimos ' + DATA.windowDays + ' dias';
  if(!items.length){
    $('feed').innerHTML = '<div class="empty">No hay noticias con estos filtros en los ultimos ' + DATA.windowDays + ' dias.</div>';
    return;
  }
  $('feed').innerHTML = items.map(i => {
    const isEmerg = i.severity === 'Critica' && i.cvss && parseFloat(i.cvss) >= UI.emergCVSS;
    const sevClass = isEmerg ? 'crit emerg-sev' : i.severity;
    const sevLabel = isEmerg ? `EMERGENCIA CVSS ${i.cvss}` : (LABEL[i.severity] || i.severity);
    return `
    <div class="item">
      <button class="sev ${esc(sevClass)}" data-sev="${esc(i.severity)}" title="Filtrar por esta severidad">
        ${esc(sevLabel)}</button>
      <div style="min-width:0">
        <a class="title" href="${esc(i.url)}" target="_blank" rel="noopener" data-news="${esc(i.url)}">${esc(i.title)}</a>${(i.alts && i.alts.length) ? ` <span class="dupbadge" data-news="${esc(i.url)}" title="${i.alts.length} noticia(s) similares o repetidas fusionadas aqui">${i.alts.length + 1}</span>` : ''}
        <div class="meta">
          <span>${i.date ? esc(i.date) : 'sin fecha'}</span>
          ${i.sources.map(s => `<a class="chip src" href="${esc(srcUrl(s))}" target="_blank" rel="noopener" title="Abrir la web de la fuente">${esc(s)}</a>`).join('')}
          ${i.cves.map(c => `<a class="chip cve" href="https://nvd.nist.gov/vuln/detail/${esc(c)}" target="_blank" rel="noopener" title="Abrir ${esc(c)} en NVD">${esc(c)} ↗</a>`).join('')}
          ${i.topics.map(t => `<button class="chip topic" data-topic="${esc(t)}" title="Filtrar por tema">${esc(t)}</button>`).join('')}
        </div>
      </div>
    </div>`;
  }).join('');
}

// Panel derecho: "Ultimas noticias" (del dia, cualquier severidad) o "Temas monitorizados"
let PANEL_VIEW = null;
function panelActual(){ return PANEL_VIEW || UI.panel || 'ultimas'; }
function renderPanelTabs(){
  const cur = panelActual();
  document.querySelectorAll('.ptab').forEach(el => el.classList.toggle('on', el.dataset.tab === cur));
}
async function renderUltimas(){
  const box = $('topics');
  box.innerHTML = '<div class="loading">Cargando ultimas noticias...</div>';
  try{
    const r = await fetch('/api/archivo?dias=365');
    if(!r.ok) throw new Error('HTTP ' + r.status);
    const body = await r.json();
    const allItems = body.items || [];
    const sorted = allItems.sort((a, b) => (b.date || '').localeCompare(a.date || ''));
    const list = sorted.slice(0, UI.top || 10);
    if(!list.length){ box.innerHTML = '<div class="empty">No hay noticias todavia.</div>'; return; }
    box.innerHTML = '<div class="topic-block"><ul>' + list.map(i => `<li style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:6px 0;border-bottom:1px solid var(--line)">
          <a href="${esc(i.url)}" target="_blank" rel="noopener" data-news="${esc(i.url)}" style="flex:1 1 100%">${esc(i.title)}</a>
          <span class="sev ${esc(i.severity)}" style="width:auto;padding:2px 6px;font-size:9.5px;cursor:default">${esc(LABEL[i.severity] || i.severity)}</span>
          <span class="dmuted" style="font-size:11px;white-space:nowrap">${esc(i.date)}</span></li>`).join('') + '</ul></div>';
  }catch(e){
    box.innerHTML = '<div class="empty">Error al cargar ultimas noticias.</div>';
  }
}
async function renderTopics(){
  renderPanelTabs();
  if(panelActual() === 'ultimas'){ await renderUltimas(); return; }
  const box = $('topics');
  const topics = DATA.topics || [];
  if(!topics.length){ box.innerHTML = '<div class="empty">Anade temas en Ajustes &rarr; Temas</div>'; return; }
  // Temas con mas noticias primero; los que no tienen novedades van al final
  const groups = topics.map(t => ({
      t,
      list: (DATA.items||[]).filter(i => i.topics.includes(t)).sort((a,b) => RANK[b.severity] - RANK[a.severity])
    })).sort((a,b) => b.list.length - a.list.length);
  box.innerHTML = groups.map(({t, list}) => {
    const top = list.slice(0,5);
    return `<div class="topic-block${list.length ? '' : ' empty-topic'}">
      <h3><span class="tname" data-topic="${esc(t)}" title="Filtrar por este tema">${esc(t)}</span><span class="chip topic" data-topic="${esc(t)}">${list.length}</span></h3>
      ${top.length ? '<ul>' + top.map(i => `<li>
          <button class="sev ${esc(i.severity)}" data-sev="${esc(i.severity)}" style="width:auto;padding:2px 6px;font-size:9.5px">${esc(LABEL[i.severity]||i.severity)}</button>
          <span style="min-width:0"><a href="${esc(i.url)}" target="_blank" rel="noopener" data-news="${esc(i.url)}">${esc(i.title)}</a>${i.date ? ` <span style="font-size:9px;color:var(--mut)">${esc(i.date)}</span>` : ''}</span></li>`).join('') + '</ul>'
        : '<div style="color:var(--mut);font-size:12px">Sin novedades en la ventana</div>'}
    </div>`;
  }).join('');
}

/* ---- Interaccion: etiquetas pulsables ---- */
function setFilter(kind, value){
  if(kind === 'sev')   { $('fSev').value = value; }
  if(kind === 'src')   { $('fSrc').value = value; }
  if(kind === 'topic') { $('fTopic').value = value; }
  renderFeed();
}
document.addEventListener('click', async e => {
  // Titulo de una noticia (feed o temas): abre el popup de detalle en vez de salir de la web
  const nw = e.target.closest('[data-news]');
  if(nw){ e.preventDefault(); openNews(nw.dataset.news); return; }
  // Etiquetas superiores (KPIs): filtran el feed o llevan al estado de fuentes
  const kpi = e.target.closest('[data-kpi]');
  if(kpi){
    const k = kpi.dataset.kpi;
    if(k === 'sources'){ $('sources').scrollIntoView({behavior:'smooth', block:'center'}); return; }
    if(k === 'estado'){
      MON_MIN = false;
      applyMon();
      $('healthBody').scrollIntoView({behavior:'smooth', block:'start'});
      return;
    }
    if(k === 'Emergencia'){
      SEARCH = { items: (DATA.items || []).filter(i => i.severity === 'Critica' && i.cvss && parseFloat(i.cvss) >= UI.emergCVSS) };
      renderFeed();
      $('feed').scrollIntoView({behavior:'smooth', block:'start'});
      return;
    }
    $('fSev').value = (k === 'all') ? '' : k;
    $('fSrc').value = ''; $('fTopic').value = '';
    renderFeed();
    $('feed').scrollIntoView({behavior:'smooth', block:'start'});
    return;
  }
  const clear = e.target.closest('[data-clear]');
  if(clear){
    const k = clear.dataset.clear;
    if(k === 'all'){ $('fSev').value=''; $('fSrc').value=''; $('fTopic').value=''; }
    if(k === 'sev') $('fSev').value='';
    if(k === 'src') $('fSrc').value='';
    if(k === 'topic') $('fTopic').value='';
    renderFeed(); return;
  }
  const tog = e.target.closest('[data-sev-toggle]');
  if(tog){ await toggleSeverity(tog.dataset.sevToggle); return; }
  const el = e.target.closest('[data-sev],[data-src],[data-topic],[data-cve]');
  if(el && !el.closest('a[href]:not(.chip)')){
    if(el.dataset.sev)   setFilter('sev', el.dataset.sev);
    else if(el.dataset.cve) setFilter('cve', el.dataset.cve);
    else if(el.dataset.topic) setFilter('topic', el.dataset.topic);
    else if(el.dataset.src) setFilter('src', el.dataset.src);
    if(el.dataset.sev || el.dataset.src || el.dataset.topic || el.dataset.cve){
      $('feed').scrollIntoView({behavior:'smooth', block:'start'});
    }
  }
});
['fSev','fSrc','fTopic'].forEach(id => $(id).onchange = renderFeed);

async function toggleSeverity(key){
  let next = ACTIVE_SEVS.includes(key) ? ACTIVE_SEVS.filter(s => s !== key) : [...ACTIVE_SEVS, key];
  if(next.length === 0){ return; }   // siempre debe quedar al menos un nivel
  next = LEVELS.map(l => l.key).filter(k => next.includes(k));
  const cfg = await getSettings();
  cfg.config.severidades = next;
  await saveSettings({config: cfg.config});   // conserva el tema y el resto de ajustes
  ACTIVE_SEVS = next;
  renderToggles();
  load(true);
}

/* ---- Ajustes ---- */
async function getSettings(){
  if(!SETTINGS){
    const r = await fetch('/api/settings');
    SETTINGS = await r.json();
  }
  return JSON.parse(JSON.stringify(SETTINGS));
}
async function saveSettings(payload){
  const r = await fetch('/api/settings', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload)});
  if(!r.ok) throw new Error('HTTP ' + r.status);
  SETTINGS = null;   // se recarga la proxima vez
  if(payload.config){
    UMB.verde = payload.config.salud_umbral_verde ?? UMB.verde;
    UMB.ambar = payload.config.salud_umbral_ambar ?? UMB.ambar;
    applyLayout(payload.config);
  }
  return r.json();
}


async function openSettings(){
  const s = await getSettings();
  $('tFuentes').value = s.fuentes;
  $('tTemas').value = s.temas;
  $('tOmitir').value = s.omitir;
  $('tServicios').value = s.estado;
  $('mMonitor').checked = !!s.config.monitor_salud;
  $('mIntervalo').value = s.config.monitor_intervalo_seg || 1800;
  $('mFont').value = s.config.tamano_letra || 14;
  $('mUmbV').value = s.config.salud_umbral_verde || 90;
  $('mUmbA').value = s.config.salud_umbral_ambar || 60;
  $('mWpct').value = s.config.ancho_pct || 100;
  $('mResumen').value = s.config.resumen_caracteres || 1000;
  $('mTamMon').value = s.config.tamano_monitor || 11;
  $('mHGen').value = s.config.horas_grafica_general || 24;
  $('mHSvc').value = s.config.horas_grafica_servicio || 2;
  $('mMinInc').value = s.config.minutos_aviso_incidencia || 15;
  $('mPanel').value = s.config.panel_derecho || 'ultimas';
  $('mTop').value = s.config.top_noticias || 10;
  $('mEmergCVSS').value = s.config.umbral_emergencia_cvss || 9.5;
  $('mMonVista').value = s.config.monitor_vista || 'max';
  $('mCols').value = s.config.casillas_fila || 8;
  $('mHook').value = s.config.webhook_url || '';
  $('mMant').value = s.config.mantenimiento || '';
  $('mDias').value = s.config.dias;
  $('mTema').value = s.config.tema || 'soc';
  $('mCache').value = s.config.noticias_intervalo_min;
  // Notificaciones
  $('mNotifHab').checked = s.config.notif_habilitado === '1';
  $('mNotifTipo').value = s.config.notif_tipo || '';
  $('mNotifAsunto').value = s.config.notif_asunto || 'ATALAYA: Alerta de seguridad';
  $('mNotifDestino').value = s.config.notif_destino || '';
  $('mGmailUser').value = s.config.notif_gmail_usuario || '';
  $('mGmailPass').value = s.config.notif_gmail_password || '';
  $('mOutlookUser').value = s.config.notif_outlook_usuario || '';
  $('mOutlookPass').value = s.config.notif_outlook_password || '';
  $('mSmtpSrv').value = s.config.notif_smtp_servidor || '';
  $('mSmtpPue').value = s.config.notif_smtp_puerto || '587';
  $('mSmtpUser').value = s.config.notif_smtp_usuario || '';
  $('mSmtpPass').value = s.config.notif_smtp_password || '';
  $('mSmtpRemit').value = s.config.notif_smtp_remitente || '';
  $('mSmtpSsl').value = s.config.notif_smtp_ssl || '1';
  updateNotifFields();
  $('mSevs').innerHTML = LEVELS.map(l => `
    <label class="tog ${s.config.severidades.includes(l.key) ? 'on' : ''}" style="cursor:pointer">
      <input type="checkbox" value="${l.key}" ${s.config.severidades.includes(l.key) ? 'checked' : ''} style="margin:0 4px 0 0"> <i style="background:${l.color}"></i>${l.label}
    </label>`).join('');
  $('mMsg').textContent = ''; $('mMsg').className = 'msg';
  $('overlay').classList.add('show');
}
function closeSettings(){
  $('overlay').classList.remove('show');
  if(SETTINGS){ applyTheme(SETTINGS.config.tema); applyFont(SETTINGS.config.tamano_letra); }   // descarta la vista previa no guardada
}

/* ---- Tamano de letra (config) ---- */
function applyFont(px){
  const n = Math.min(20, Math.max(11, Number(px) || 14));
  document.body.style.fontSize = n + 'px';
}

/* ---- Tema visual ---- */
function applyTheme(name){
  const ok = ['profesional','corporativo'];
  const t = ok.includes(name) ? name : 'profesional';
  document.body.className = 'theme-' + t;
  placeKpis(t === 'corporativo');
}
// En corporativo, las etiquetas de totales pasan a la barra lateral; en el resto, arriba del contenido
function placeKpis(side){
  const k = document.querySelector('.kpis'); if(!k) return;
  if(side){
    const b = document.querySelector('header .brand');
    if(b && k.parentElement.tagName !== 'HEADER') b.after(k);
  } else if(k.parentElement.tagName !== 'MAIN'){
    document.querySelector('main').prepend(k);
  }
}
$('mTema').onchange = () => applyTheme($('mTema').value);

/* ---- Notificaciones por correo ---- */
function updateNotifFields(){
  const tipo = $('mNotifTipo').value;
  $('gmailFields').style.display = (tipo === 'gmail') ? 'block' : 'none';
  $('outlookFields').style.display = (tipo === 'outlook') ? 'block' : 'none';
  $('smtpFields').style.display = (tipo === 'smtp') ? 'block' : 'none';
}
$('mNotifTipo').onchange = updateNotifFields;

document.querySelectorAll('.tab').forEach(t => t.onclick = () => {
  document.querySelectorAll('.tab').forEach(x => x.classList.toggle('on', x === t));
  ['config','fuentes','temas','omitir','servicios','notificaciones'].forEach(n => $('tab-' + n).classList.toggle('hidden', t.dataset.tab !== n));
});

$('btnSettings').onclick = openSettings;
$('mClose').onclick = closeSettings;
$('mCancel').onclick = closeSettings;
$('overlay').onclick = e => { if(e.target.id === 'overlay') closeSettings(); };

$('mSave').onclick = async () => {
  const sevs = [...document.querySelectorAll('#mSevs input:checked')].map(i => i.value);
  const msg = $('mMsg');
  if(sevs.length === 0){ msg.textContent = 'Marca al menos un nivel de severidad.'; msg.className = 'msg err'; return; }
  msg.textContent = 'Guardando...'; msg.className = 'msg';
  try{
    await saveSettings({
      fuentes: $('tFuentes').value,
      temas:   $('tTemas').value,
      omitir:  $('tOmitir').value,
      estado:  $('tServicios').value,
      config:  { severidades: sevs, dias: Number($('mDias').value), noticias_intervalo_min: Number($('mCache').value), tema: $('mTema').value, monitor_salud: $('mMonitor').checked, monitor_intervalo_seg: Number($('mIntervalo').value), tamano_letra: Number($('mFont').value), salud_umbral_verde: Number($('mUmbV').value), salud_umbral_ambar: Number($('mUmbA').value), ancho_pct: Number($('mWpct').value), resumen_caracteres: Number($('mResumen').value), tamano_monitor: Number($('mTamMon').value), horas_grafica_general: Number($('mHGen').value), horas_grafica_servicio: Number($('mHSvc').value), minutos_aviso_incidencia: Number($('mMinInc').value), casillas_fila: Number($('mCols').value), webhook_url: $('mHook').value.trim(), mantenimiento: $('mMant').value.trim(), panel_derecho: $('mPanel').value, top_noticias: Number($('mTop').value), umbral_emergencia_cvss: Number($('mEmergCVSS').value), monitor_vista: $('mMonVista').value, notif_habilitado: $('mNotifHab').checked ? '1' : '0', notif_tipo: $('mNotifTipo').value, notif_asunto: $('mNotifAsunto').value, notif_destino: $('mNotifDestino').value, notif_gmail_usuario: $('mGmailUser').value, notif_gmail_password: $('mGmailPass').value, notif_outlook_usuario: $('mOutlookUser').value, notif_outlook_password: $('mOutlookPass').value, notif_smtp_servidor: $('mSmtpSrv').value, notif_smtp_puerto: Number($('mSmtpPue').value) || 587, notif_smtp_usuario: $('mSmtpUser').value, notif_smtp_password: $('mSmtpPass').value, notif_smtp_remitente: $('mSmtpRemit').value, notif_smtp_ssl: $('mSmtpSsl').value }
    });
    ACTIVE_SEVS = LEVELS.map(l => l.key).filter(k => sevs.includes(k));
    closeSettings();
    load(true);
    refreshHealth();
  }catch(e){
    msg.textContent = 'Error al guardar: ' + e.message; msg.className = 'msg err';
  }
};

// Actualizar: recopila noticias de nuevo y comprueba los servicios a la vez
$('btnRefresh').onclick = () => Promise.all([load(true), refreshHealth()]);

/* ---- Gauge semicircular simple: arco de color unico + resto atenuado ---- */
function arcRendimiento(pct){
  const radius = 65;
  const cx = 100;
  const cy = 100;

  // Color y estado segun los umbrales configurados (verde / ambar / rojo)
  const uv = (typeof UMB !== 'undefined' && UMB.verde) || 90;
  const ua = (typeof UMB !== 'undefined' && UMB.ambar) || 60;
  let col = '#d93025', estado = 'Critico';
  if (pct >= uv) { col = '#2e9e5b'; estado = 'Optimo'; }
  else if (pct >= ua) { col = '#e8a317'; estado = 'Degradado'; }

  const animar = !window.__hsDone;
  window.__hsDone = true;
  const arc = `M ${cx - radius} ${cy} A ${radius} ${radius} 0 0 1 ${cx + radius} ${cy}`;

  return `<div class="hscore">
    <svg viewBox="0 0 200 118" width="170" height="100" style="display:block;overflow:visible">
      <path d="${arc}" pathLength="100" stroke="${col}" stroke-opacity="0.16" stroke-width="14" fill="none" stroke-linecap="round"/>
      <path d="${arc}" pathLength="100" class="${animar ? 'hs-anim' : ''}" stroke="${col}" stroke-width="14" fill="none" stroke-linecap="round" style="stroke-dasharray:${Math.max(pct, 0.01)} 100;--hs:${Math.max(pct, 0.01)}"/>
      <text x="100" y="86" text-anchor="middle" font-size="30" font-weight="700" fill="${col}" font-family="Segoe UI, Arial, sans-serif">${pct}%</text>
      <text x="100" y="106" text-anchor="middle" font-size="11" font-weight="700" letter-spacing="1.2" fill="${col}" font-family="Segoe UI, Arial, sans-serif">${estado.toUpperCase()}</text>
    </svg>
    <div class="hscore-lbl">Health Score</div>
  </div>`;
}

/* ---- Notificaciones por correo de eventos ---- */
async function sendEventNotification(type, title, description, extraData){
  try{
    const payload = {type, title, description, ...extraData};
    await fetch('/api/event-notificacion', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload)});
  }catch(e){}   // Error silencioso, no afecta la UX
}

/* ---- Monitor de salud de servicios ---- */
let HEALTH = null;
async function loadHealth(force){
  try{
    const r = await fetch('/api/health' + (force ? '?refresh=1' : ''));
    if(!r.ok) throw new Error('HTTP ' + r.status);
    HEALTH = await r.json();
    renderHealth();
    checkServices();
  }catch(e){
    $('healthBody').innerHTML = '<div class="empty">No se pudo consultar el monitor (' + esc(e.message) + ').</div>';
  }
}

// Grafica dinamica de tiempos de respuesta (ms) por servicio, con el historico guardado
function timeChart(svcs){
  const W = 640, H = 150, pl = 40, pb = 18;
  const all = svcs.flatMap(s => (s.history || []).map(p => p.ms));
  if(!all.length) return '';
  const max = Math.max(100, ...all);
  const len = Math.max(2, ...svcs.map(s => (s.history || []).length));
  const colors = ['#2f6fb0','#2e8b57','#d4621f','#8e44ad','#b3261e','#17a2b8'];
  const lines = svcs.map((s, si) => {
    const h = s.history || [];
    const c = colors[si % colors.length];
    const pts = h.map((p, i) => (pl + i * (W - pl - 8) / (len - 1)).toFixed(1) + ',' +
                                (H - pb - (p.ms / max) * (H - pb - 10)).toFixed(1)).join(' ');
    return `<polyline fill="none" stroke="${c}" stroke-width="2" points="${pts}"/>
            <text x="${W - 4}" y="${12 + si * 12}" text-anchor="end" font-size="10" fill="${c}">${esc(s.name)}</text>`;
  }).join('');
  return `<div style="padding:4px 14px 14px">
    <div class="hmeta" style="margin-bottom:6px">Tiempo de respuesta (ms) a lo largo del tiempo &middot; escala maxima ${max} ms</div>
    <svg viewBox="0 0 ${W} ${H}" width="100%" height="170" preserveAspectRatio="none"
         style="display:block;border:1px solid var(--line);border-radius:6px;background:var(--panel2)">
      <line x1="${pl}" y1="10" x2="${W - 8}" y2="10" stroke="var(--line2)" stroke-dasharray="3 3"/>
      <line x1="${pl}" y1="${H - pb}" x2="${W - 8}" y2="${H - pb}" stroke="var(--line2)"/>
      ${lines}</svg></div>`;
}

// Puntuacion de salud: OK = 100, AVISO = 50, caida = 0
const scoreOf = st => st === 'OK' ? 100 : ((st === 'AVISO' || st === 'LENTO') ? 50 : 0);
const stColor = st => st === 'OK' ? '#2e8b57' : ((st === 'AVISO' || st === 'LENTO') ? '#b07d06' : '#b3261e');
const pc = v => v == null ? '-' : v + '%';
// Diseño (config.txt: ancho_pct, casillas_fila)
let UI = {cols: 8, hGen: 24, hSvc: 2, minInc: 15, dias: 2, panel: 'ultimas', top: 10, emergCVSS: 9.5};
let MON_MIN = false;   // monitor de salud minimizado (config: monitor_vista)
function applyLayout(c){
  UI.cols = c.casillas_fila || 8;
  UI.hGen = c.horas_grafica_general || 24;
  UI.hSvc = c.horas_grafica_servicio || 2;
  UI.minInc = c.minutos_aviso_incidencia || 15;
  UI.dias = c.dias || 2;
  UI.panel = c.panel_derecho || 'ultimas';
  UI.top = c.top_noticias || 10;
  UI.emergCVSS = c.umbral_emergencia_cvss || 9.5;
  MON_MIN = (c.monitor_vista === 'min');
  applyMon();
  document.documentElement.style.setProperty('--mon-fs', (c.tamano_monitor || 11) + 'px');
  document.documentElement.style.setProperty('--wpct', (c.ancho_pct || 100) + '%');
}
// Umbrales del estado general (config.txt: salud_umbral_verde / salud_umbral_ambar)
let UMB = {verde: 90, ambar: 60};
const tierColor = p => p >= UMB.verde ? '#2e8b57' : (p >= UMB.ambar ? '#b07d06' : '#b3261e');

// Tramos de linea: cada tramo se pinta con el color de su punto final
function segLines(pts, colorOf){
  let out = '';
  for(let i = 1; i < pts.length; i++){
    out += `<line x1="${pts[i-1][0]}" y1="${pts[i-1][1]}" x2="${pts[i][0]}" y2="${pts[i][1]}" stroke="${colorOf(i)}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>`;
  }
  return out;
}

// Historial de incidencias de los ultimos 30 dias (desplegable)
function buildHist(svcs){
  const all = svcs.flatMap(s => (s.incidents || []).map(i => ({...i, name: s.name})));
  if(!all.length) return '<div class="hmeta" style="padding:0 16px 12px">Sin incidencias en los ultimos 30 dias.</div>';
  all.sort((a, b) => (a.start < b.start ? 1 : -1));
  return `<details class="hist"><summary>Historial de incidencias (30 dias): ${all.length}</summary>
    <table><thead><tr><th>Servicio</th><th>Inicio</th><th>Fin</th><th>Duracion</th><th>Estado</th></tr></thead><tbody>
    ${all.slice(0, 100).map(i => `<tr><td>${esc(i.name)}</td><td>${esc(i.start)}</td><td>${i.ongoing ? 'en curso' : esc(i.end)}</td><td>${i.min} min</td><td>${esc(i.status)}</td></tr>`).join('')}
    </tbody></table></details>`;
}

// Fechas del historico ("yyyy-MM-dd HH:mm:ss") y filtro por ventana en horas
const tDate = t => new Date(String(t || '').replace(' ', 'T'));
function winHist(hist, hrs){
  const from = Date.now() - hrs * 36e5;
  return (hist || []).filter(p => tDate(p.t).getTime() >= from);
}
function sameDay(t){ return tDate(t).toDateString() === new Date().toDateString(); }

// Grafica del dia actual (de 00:00 a 24:00) con la linea de "ahora"
function dayChartBox(title, pts, yMax, unit){
  const W = 800, H = 56, pl = 40, pr = 10, pt = 6, pb = 16;
  const iw = W - pl - pr, ih = H - pt - pb;
  // El eje va desde la primera metrica hasta la ultima del dia (sin tramos vacios)
  let t0 = pts.length ? Math.min(...pts.map(p => p.ms)) : 0;
  let t1 = pts.length ? Math.max(...pts.map(p => p.ms)) : 1;
  if(t1 - t0 < 60000){ t0 -= 1800e3; t1 += 1800e3; }
  const xOf = ms => pl + ((ms - t0) / (t1 - t0)) * iw;
  const yOf = v => pt + ih - Math.max(0, Math.min(1, v / yMax)) * ih;
  let grid = '';
  for(let k = 0; k <= 4; k++){
    const v = yMax * k / 4, y = yOf(v).toFixed(1);
    grid += `<line x1="${pl}" x2="${W - pr}" y1="${y}" y2="${y}" stroke="var(--line)"/><text x="${pl - 6}" y="${(+y + 4).toFixed(1)}" text-anchor="end" font-size="5.5" fill="var(--mut)">${Math.round(v)}${unit}</text>`;
  }
  for(let k = 0; k <= 4; k++){
    const ms = t0 + (t1 - t0) * k / 4;
    grid += `<text x="${xOf(ms).toFixed(1)}" y="${H - 5}" text-anchor="middle" font-size="5" fill="var(--mut)">${new Date(ms).toTimeString().slice(0, 5)}</text>`;
  }
  const P = pts.map(p => [xOf(p.ms).toFixed(1), yOf(p.v).toFixed(1), p]);
  let lines = '';
  for(let i = 1; i < P.length; i++){
    lines += `<line x1="${P[i-1][0]}" y1="${P[i-1][1]}" x2="${P[i][0]}" y2="${P[i][1]}" stroke="${P[i][2].color}" stroke-width="2.2" stroke-linecap="round"/>`;
  }
  // Punto visible + zona de paso del raton mas grande (muestra hora y plataforma)
  const dots = P.map(([x, y, p]) => `<circle cx="${x}" cy="${y}" r="2.8" fill="${p.color}"/><circle cx="${x}" cy="${y}" r="9" fill="transparent"><title>${esc(p.title)}</title></circle>`).join('');
  const body = pts.length
    ? `<svg class="dchart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)}">${grid}${lines}${dots}</svg>`
    : '<div class="dmuted">Todavia no hay datos de hoy.</div>';
  return `<fieldset class="fsrc dchartbox"><legend>${esc(title)} · hoy</legend>${body}</fieldset>`;
}

// Fecha corta "dd/MM HH:mm" (historico.txt guarda "yyyy-MM-dd HH:mm:ss")
function shortT(t){
  const m = String(t || '').match(/(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2})/);
  return m ? m[3] + '/' + m[2] + ' ' + m[4] : String(t || '');
}
// Serie del estado general a lo largo del tiempo (media de los servicios, alineada por el final)
function healthSeries(svcs){
  // La grafica principal solo usa las ultimas horas_grafica_general horas
  svcs = svcs.map(s => ({...s, history: winHist(s.history, UI.hGen)}));
  const maxLen = Math.max(0, ...svcs.map(s => (s.history || []).length));
  const out = [];
  for(let p = 0; p < maxLen; p++){
    let sum = 0, cnt = 0, t = '', ms = 0;
    const down = [];
    for(const s of svcs){
      const h = s.history || [];
      const idx = h.length - maxLen + p;
      if(idx < 0) continue;
      sum += scoreOf(h[idx].status); cnt++;
      if(!t){ t = shortT(h[idx].t); ms = tDate(h[idx].t).getTime(); }
      if(h[idx].status === 'CAIDA' || h[idx].status === 'SIN RESPUESTA') down.push(s.name);
    }
    if(cnt) out.push({v: sum / cnt, t, down, ms});
  }
  return out;
}

// Incidencias: tramos en los que el estado general queda por debajo del umbral verde
function incidents(series){
  const out = [];
  let cur = null;
  series.forEach((p, i) => {
    if(p.v < UMB.verde){
      if(!cur) cur = {from: i, end: null, lvl: p.v, names: new Set()};
      cur.lvl = Math.min(cur.lvl, p.v);
      p.down.forEach(n => cur.names.add(n));
    } else if(cur){
      cur.end = i; out.push(cur); cur = null;
    }
  });
  if(cur) out.push(cur);
  return out.map(c => ({
    from: c.from, end: c.end, lvl: c.lvl,
    start: series[c.from].t, startMs: series[c.from].ms, stop: c.end != null ? series[c.end].t : null,
    names: [...c.names]
  }));
}
function incText(c){
  return 'Detectada ' + c.start + ' · ' + (c.names.length ? c.names.join(', ') : 'origen no identificado') + (c.stop ? ' · normalidad ' + c.stop : ' · en curso');
}
function incTitle(c){
  return 'Caidos: ' + (c.names.join(', ') || 'ninguno registrado') + ' · ' + incText(c);
}

// Tangentes monotonas: la curva suaviza la linea sin sobrepasar los datos
function monoPath(P){
  const n = P.length;
  if(n < 3) return 'M' + P.map(p => p[0].toFixed(1) + ',' + p[1].toFixed(1)).join(' L');
  const dx = [], sl = [];
  for(let i = 0; i < n - 1; i++){ dx.push(P[i+1][0] - P[i][0] || 1e-6); sl.push((P[i+1][1] - P[i][1]) / dx[i]); }
  const m = [sl[0]];
  for(let i = 1; i < n - 1; i++) m.push(sl[i-1] * sl[i] <= 0 ? 0 : (sl[i-1] + sl[i]) / 2);
  m.push(sl[n-2]);
  for(let i = 0; i < n - 1; i++){
    if(sl[i] === 0){ m[i] = 0; m[i+1] = 0; continue; }
    const a = m[i] / sl[i], b = m[i+1] / sl[i], s = a * a + b * b;
    if(s > 9){ const t = 3 / Math.sqrt(s); m[i] = t * a * sl[i]; m[i+1] = t * b * sl[i]; }
  }
  let d = `M${P[0][0].toFixed(1)},${P[0][1].toFixed(1)}`;
  for(let i = 0; i < n - 1; i++){
    const h = dx[i] / 3;
    d += ` C${(P[i][0] + h).toFixed(1)},${(P[i][1] + m[i] * h).toFixed(1)} ${(P[i+1][0] - h).toFixed(1)},${(P[i+1][1] - m[i+1] * h).toFixed(1)} ${P[i+1][0].toFixed(1)},${P[i+1][1].toFixed(1)}`;
  }
  return d;
}

// Grafica general: curva suave por niveles, ejes con escala, incidencias, marcador "ahora" y cursor con detalle
function healthChart(series, inc, W){
  if(series.length < 2) return '';
  const H = 96, pl = 26, pr = 8, top = 8, bot = 16;
  const pw = W - pl - pr, ph = H - top - bot;
  const xOf = i => pl + i * pw / (series.length - 1);
  const yOf = v => top + (100 - v) / 100 * ph;
  const uv = UMB.verde, ua = UMB.ambar;
  const P = series.map((p, i) => [xOf(i), yOf(p.v)]);
  const line = monoPath(P);
  const base = top + ph;
  const area = `${line} L${P[P.length-1][0].toFixed(1)},${base} L${P[0][0].toFixed(1)},${base} Z`;
  const lastV = series[series.length - 1].v, nowCol = tierColor(lastV);

  // Degradado horizontal: el trazo cambia de color segun el nivel de cada tramo
  let stops = '', prev = null;
  series.forEach((p, i) => {
    const c = tierColor(p.v);
    if(c === prev && i < series.length - 1) return;
    stops += `<stop offset="${((xOf(i) - pl) / pw * 100).toFixed(2)}%" stop-color="${c}"/>`;
    prev = c;
  });

  let g = `<defs>
    <linearGradient id="hcLine" gradientUnits="userSpaceOnUse" x1="${pl}" y1="0" x2="${pl + pw}" y2="0">${stops}</linearGradient>
    <linearGradient id="hcArea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${nowCol}" stop-opacity=".24"/><stop offset="1" stop-color="${nowCol}" stop-opacity="0"/></linearGradient>
    <clipPath id="hcClip"><rect x="${pl}" y="${top - 2}" width="${pw}" height="${ph + 4}"/></clipPath>
  </defs>`;

  // Zona de riesgo (por debajo del umbral ambar) y rejilla
  g += `<rect x="${pl}" y="${yOf(ua)}" width="${pw}" height="${base - yOf(ua)}" fill="#d93025" opacity=".05"/>`;
  [[100, ''], [uv, 'verde'], [ua, 'ambar'], [0, '']].forEach(([v, lab]) => {
    const dash = lab ? ' stroke-dasharray="3 3"' : '';
    g += `<line x1="${pl}" x2="${pl + pw}" y1="${yOf(v)}" y2="${yOf(v)}" stroke="var(--line2)" stroke-width="${lab ? .8 : .5}"${dash} opacity="${lab ? .9 : .6}"/>`;
    g += `<text x="${pl - 5}" y="${yOf(v) + 3}" text-anchor="end" font-size="8.5" fill="var(--mut)">${v}</text>`;
  });

  // Tramos de incidencia
  inc.forEach(c => {
    const x1 = xOf(c.from), x2 = xOf(c.end != null ? c.end : series.length - 1);
    g += `<rect x="${x1}" y="${top}" width="${Math.max(3, x2 - x1)}" height="${ph}" fill="${tierColor(c.lvl)}" opacity=".12"><title>${esc(incTitle(c))}</title></rect>`;
  });

  // Area + curva
  g += `<g clip-path="url(#hcClip)"><path d="${area}" fill="url(#hcArea)"/><path d="${line}" fill="none" stroke="url(#hcLine)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></g>`;

  // Inicio / fin de incidencias
  inc.forEach(c => {
    g += `<circle cx="${xOf(c.from).toFixed(1)}" cy="${yOf(series[c.from].v).toFixed(1)}" r="3" fill="#fff" stroke="${tierColor(c.lvl)}" stroke-width="1.6"><title>Inicio del problema: ${esc(c.start)} · origen: ${esc(c.names.join(', ') || 'no identificado')}</title></circle>`;
    if(c.end != null) g += `<circle cx="${xOf(c.end).toFixed(1)}" cy="${yOf(series[c.end].v).toFixed(1)}" r="3" fill="#fff" stroke="#2e8b57" stroke-width="1.6"><title>Fin del problema (normalidad): ${esc(c.stop)}</title></circle>`;
  });

  // Eje de tiempo
  for(let k = 0; k <= 3; k++){
    const i = Math.round(k * (series.length - 1) / 3);
    const t = k === 0 || k === 3 ? series[i].t : new Date(series[i].ms).toTimeString().slice(0, 5);
    g += `<text x="${xOf(i)}" y="${H - 3}" text-anchor="${k === 0 ? 'start' : (k === 3 ? 'end' : 'middle')}" font-size="8.5" fill="var(--mut)">${esc(t)}</text>`;
  }

  // Marcador "ahora"
  const lx = P[P.length - 1][0], ly = P[P.length - 1][1];
  g += `<circle class="hc-pulse" cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" r="5" fill="${nowCol}"/><circle cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" r="3.4" fill="${nowCol}" stroke="#fff" stroke-width="1.5"/>`;

  // Cursor interactivo
  g += `<g class="hc-cross" style="display:none"><line y1="${top}" y2="${base}" stroke="var(--mut)" stroke-width=".8" stroke-dasharray="2 2"/><circle r="3.6" fill="#fff" stroke-width="2"/></g>`;
  g += `<rect class="hc-hit" x="${pl}" y="${top}" width="${pw}" height="${ph}" fill="transparent"/>`;

  window.__HC = {series, pl, pw, W, H, top, ph};
  return `<div class="hc2"><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Estado general de salud">${g}</svg><div class="hc-tip"></div></div>`;
}

document.addEventListener('mousemove', e => {
  const wrap = e.target.closest && e.target.closest('.hc2');
  document.querySelectorAll('.hc2').forEach(w => {
    if(w !== wrap){ w.querySelector('.hc-cross').style.display = 'none'; w.querySelector('.hc-tip').style.display = 'none'; }
  });
  const C = window.__HC;
  if(!wrap || !C || !e.target.classList.contains('hc-hit')) return;
  const svg = wrap.querySelector('svg'), r = svg.getBoundingClientRect(), k = r.width / C.W;
  const x = (e.clientX - r.left) / k;
  const i = Math.max(0, Math.min(C.series.length - 1, Math.round((x - C.pl) / C.pw * (C.series.length - 1))));
  const p = C.series[i];
  const px = C.pl + i * C.pw / (C.series.length - 1), py = C.top + (100 - p.v) / 100 * C.ph;
  const col = tierColor(p.v);
  const cross = wrap.querySelector('.hc-cross');
  cross.style.display = '';
  const ln = cross.querySelector('line'), dot = cross.querySelector('circle');
  ln.setAttribute('x1', px); ln.setAttribute('x2', px);
  dot.setAttribute('cx', px); dot.setAttribute('cy', py); dot.setAttribute('stroke', col);
  const tip = wrap.querySelector('.hc-tip');
  tip.innerHTML = `<b style="color:${col}">${Math.round(p.v)}%</b> · ${esc(p.t)}${p.down.length ? '<br>Caidos: ' + esc(p.down.join(', ')) : ''}`;
  tip.style.display = 'block';
  tip.style.left = Math.min(Math.max(px * k, 60), r.width - 60) + 'px';
  tip.style.top = Math.max(py * k - 8, 0) + 'px';
});

function updateHealthKpi(pct){
  const kEl = $('kEstado');
  const kPctEl = $('kEstadoPct');
  if(!kEl || !kPctEl) return;
  kPctEl.textContent = pct + '%';
  const col = tierColor(pct);
  kEl.style.borderLeftColor = col;
  kEl.classList.toggle('sok', pct >= UMB.verde);
  kEl.classList.toggle('swarn', pct < UMB.verde && pct >= UMB.ambar);
  kEl.classList.toggle('sbad', pct < UMB.ambar);
}

function renderHealth(){
  const box = $('healthBody');
  if(!HEALTH || !HEALTH.enabled){
    box.innerHTML = '<div class="empty">Monitor desactivado. Activalo en Ajustes &rarr; Busqueda &rarr; General.</div>';
    updateHealthKpi(0);
    return;
  }
  const svcs = HEALTH.services || [];
  if(!svcs.length){ box.innerHTML = '<div class="empty">Anade servicios en Ajustes &rarr; Servicios.</div>'; updateHealthKpi(0); return; }
  const n = svcs.length;

  // Estado general: porcentaje de salud actual y su evolucion
  const pct = Math.round(svcs.reduce((a, s) => a + scoreOf(s.status), 0) / n);
  updateHealthKpi(pct);
  const gCol = tierColor(pct);
  const series = healthSeries(svcs);
  const inc = incidents(series);
  const gChart = healthChart(series, inc, Math.max(280, (box.clientWidth || 900) - 330));
  // El aviso de incidencia solo se muestra durante minutos_aviso_incidencia tras la deteccion
  const lastInc = (inc.length && (Date.now() - inc[inc.length - 1].startMs) <= UI.minInc * 6e4) ? inc[inc.length - 1] : null;
  const incLine = lastInc ? `<div class="hinc" style="color:${tierColor(lastInc.lvl)}" title="${esc(incTitle(lastInc))}">${esc(incText(lastInc))}</div>` : '';
  const gaugeHtml = arcRendimiento(pct);
  const general = `<div class="hgen" data-gen="1" title="Pulsa para ver el detalle" style="border-color:${gCol}">
      <div class="hgenpct" style="padding:0">${gaugeHtml}</div>
      <div style="flex:1;min-width:0">

        ${gChart}
        ${incLine}
      </div>
      <div class="hmeta" style="text-align:right">${svcs.filter(s => s.status === 'OK').length}/${n} OK</div>
    </div>`;

  // Una tarjeta por servicio. Linea verde = OK (2xx/3xx), ambar = AVISO (4xx), roja = KO (caida)
  const W = 240, H = 30, top = 5, mid = 15, bot = 25;
  const yOf = st => st === 'OK' ? top : ((st === 'AVISO' || st === 'LENTO') ? mid : bot);
  const cards = svcs.map(s => {
    const hist = winHist(s.history, UI.hSvc);
    const m = hist.length;
    const col = stColor(s.status);
    const xOf = i => m > 1 ? i * W / (m - 1) : W / 2;
    const pts = hist.map((p, i) => [xOf(i).toFixed(1), yOf(p.status).toFixed(1)]);
    const dots = hist.map((p, i) => `<circle cx="${xOf(i).toFixed(1)}" cy="${yOf(p.status).toFixed(1)}" r="2.5" fill="${stColor(p.status)}"><title>${esc(p.t)} · ${esc(p.status)} · ${p.ms} ms</title></circle>`).join('');
    const first = m ? shortT(hist[0].t) : '', last = m ? shortT(hist[m - 1].t).split(' ').pop() : '';
    const u = s.uptime || {};
    return `<div class="hcard" data-svc="${esc(s.name)}" title="Pulsa para ver el detalle. URL analizada: ${esc(s.target)}">
      <div class="hhead"><span class="dot" style="background:${col}"></span><b title="URL analizada: ${esc(s.target)}">${esc(s.name)}</b>
        <span class="hstate" style="color:${col}">${esc(s.status)}</span></div>
      <div class="hmeta">${s.kind === 'http' ? 'HTTP ' + (s.code || '-') : esc((s.kind || '').toUpperCase() + ' ' + (s.target || ''))} &middot; ${s.ms} ms</div>
      <div class="hmeta" style="color:var(--crit)" title="${esc(s.error || '')}">${s.error ? esc(s.error) : '&nbsp;'}</div>
      <svg class="hchart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Grafica de salud de ${esc(s.name)}">
        <line x1="0" y1="${top}" x2="${W}" y2="${top}" stroke="var(--line2)" stroke-dasharray="3 3"/>
        <line x1="0" y1="${bot}" x2="${W}" y2="${bot}" stroke="var(--line2)" stroke-dasharray="3 3"/>
        ${segLines(pts, i => stColor(hist[i].status))}
        ${dots}
      </svg>
      <div class="hlabels"><span>${esc(first)}</span><span>${esc(last)}</span></div>
    </div>`;
  }).join('');

  const histHtml = buildHist(svcs);
  box.innerHTML = general + `<div class="hgrid" style="grid-template-columns:repeat(${Math.min(n, UI.cols)},minmax(0,1fr))">${cards}</div><br>
    ${histHtml}`;
}

// La comprobacion la hace monitor.ps1 en segundo plano; la web solo lee health.json
// Tras pedir una comprobacion, espera a que el monitor escriba health.json nuevo (max. ~60 s)
async function refreshHealth(){
  const before = HEALTH ? HEALTH.generated : '';
  try{ await fetch('/api/health?refresh=1'); }catch(e){}
  for(let i = 0; i < 30; i++){
    await new Promise(res => setTimeout(res, 2000));
    await loadHealth(false);
    if(HEALTH && HEALTH.generated !== before) break;
  }
}
$('btnHealth').onclick = refreshHealth;

/* ---- Detalle (popups): estado general y servicios, con periodo 24 h / 7 d / 30 d ---- */
let DETAIL = {kind: null, name: null, dias: 1};
const pad2 = n => String(n).padStart(2, '0');
// Fecha de corte local en formato "yyyy-MM-dd HH:mm" (para comparar con las incidencias)
function cutoffStr(dias){
  const d = new Date(Date.now() - dias * 864e5);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}
// "yyyy-MM-dd HH:mm:ss" -> fecha dd/MM/yyyy y hora HH:mm:ss
function dtParts(t){
  const m = String(t || '').match(/(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2}(?::\d{2})?)/);
  return m ? {d: m[3] + '/' + m[2] + '/' + m[1], h: m[4]} : {d: '', h: String(t || '')};
}
async function fetchRows(svc, dias){
  const r = await fetch('/api/historico?dias=' + dias + (svc ? '&svc=' + encodeURIComponent(svc) : ''));
  if(!r.ok) throw new Error('HTTP ' + r.status);
  const x = await r.json();
  return Array.isArray(x) ? x : (x ? [x] : []);
}
function spanBtns(dias){
  return `<div class="span">${[[1, '24 h'], [7, '7 dias'], [30, '30 dias']].map(([n, l]) =>
    `<button class="spanbtn ${dias == n ? 'on' : ''}" data-dias="${n}">${l}</button>`).join('')}</div>`;
}
function showDetail(title, body){
  $('dTitle').textContent = title;
  // El popup de noticia es mas estrecho (70 %) que el de monitorizacion (80 %)
  document.querySelector('#detailOverlay .detail-box').classList.toggle('news', title === 'Noticia');
  document.querySelector('#detailOverlay .detail-box').classList.toggle('estado', title === 'Estado ATALAYA');
  $('dBody').innerHTML = body;
  $('detailOverlay').classList.add('show');
}
function incTable(list){
  if(!list.length) return '<div class="dmuted">Sin incidencias en el periodo.</div>';
  return `<div class="dtab"><table><thead><tr><th>Servicio</th><th>Inicio</th><th>Fin</th><th>Duracion</th><th>Estado</th></tr></thead><tbody>` +
    list.map(i => `<tr><td>${esc(i.name)}</td><td>${esc(i.start)}</td><td>${i.ongoing ? 'en curso' : esc(i.end)}</td><td>${i.min} min</td><td>${esc(i.status)}</td></tr>`).join('') +
    `</tbody></table></div>`;
}

// Popup de una noticia: titulo, gravedad, fecha y hora, fuente, temas, CVE y resumen
function openNews(url){
  const i = ((DATA && DATA.items) || []).find(x => x.url === url);
  if(!i){ window.open(url, '_blank', 'noopener'); return; }
  const cves = i.cves.length
    ? i.cves.map(c => `<a class="chip cve" href="https://nvd.nist.gov/vuln/detail/${esc(c)}" target="_blank" rel="noopener">${esc(c)} ↗</a>`).join(' ')
    : '<span class="dmuted">ninguno</span>';
  // Vinculadas: avisos repetidos (misma noticia en otra fuente) + noticias con el mismo CVE o tema
  const alts = i.alts || [];
  const seenU = new Set([i.url]);
  const related = [];
  for(const a of alts){ if(!seenU.has(a.url)){ seenU.add(a.url); related.push({title: a.title, url: a.url, source: a.source, why: 'repetida'}); } }
  for(const x of (DATA.items || [])){
    if(seenU.has(x.url)) continue;
    const byCve = x.cves.some(c => i.cves.includes(c));
    const byTopic = x.topics.some(t => i.topics.includes(t));
    if(byCve || byTopic){ seenU.add(x.url); related.push({title: x.title, url: x.url, source: x.sources.join(', '), why: byCve ? 'mismo CVE' : 'mismo tema'}); }
  }
  const repeats = related.length
    ? related.slice(0, 15).map(a => `<div style="margin:6px 0"><a href="${esc(a.url)}" target="_blank" rel="noopener" style="font-weight:600">${esc(a.title)}</a> <span class="dmuted">· ${esc(a.source)} · ${esc(a.why)}</span></div>`).join('')
    : '<div class="dmuted">No hay noticias vinculadas.</div>';
  showDetail('Noticia', `
    <div>
      <div style="display:flex;gap:10px;align-items:flex-start">
        <span class="sev ${esc(i.severity)}" style="width:auto;padding:6px 12px;flex:none">${esc(LABEL[i.severity] || i.severity)}${i.cvss ? ' · CVSS ' + i.cvss : ''}</span>
        <b style="font-size:16px;line-height:1.35">${esc(i.title)}</b>
      </div>
      <fieldset class="fsrc"><legend>Fuente</legend><b>${esc(i.sources.join(', '))}</b></fieldset>
    </div>
    <div class="dgrid">
      <div class="dbox"><b>${esc(i.date || 'sin fecha')}</b><span>Fecha y hora</span></div>
      <div class="dbox"><b>${esc(i.topics.join(', ') || '-')}</b><span>Sistema / tema involucrado</span></div>
      <div class="dbox"><b>${i.cves.length}</b><span>CVE</span></div>
      <div class="dbox"><b>${alts.length}</b><span>Avisos repetidos</span></div>
    </div>
    <div class="dsec"><h4>CVE</h4>${cves}</div>
    <div class="dsec"><h4>Resumen</h4><div style="font-size:13px;line-height:1.55;white-space:pre-wrap">${esc(i.summary || 'Sin resumen disponible.')}</div></div>
    <div class="dsec"><h4>Noticias vinculadas o similares (pulsa para abrir)</h4>${repeats}</div>
    <a class="btn primary" style="display:block;width:40%;margin:4px auto 0;text-align:center;box-sizing:border-box;padding:10px;font-weight: bold;" href="${esc(i.url)}" target="_blank" rel="noopener">Mostrar fuente</a>`);
}

async function openGeneral(dias){
  dias = dias || DETAIL.dias || 1;
  DETAIL = {kind: 'gen', name: null, dias};
  const svcs = (HEALTH && HEALTH.services) || [];
  const cut = cutoffStr(dias);
  let rows = [];
  try { rows = await fetchRows('', dias); } catch(e) {}
  const allowed = new Set(svcs.map(s => s.name));
  rows = rows.filter(r => allowed.has(r.name));
  // Una "comprobacion" = todos los servicios revisados en el mismo ciclo
  const cycles = new Map();
  for(const r of rows){
    if(!cycles.has(r.t)) cycles.set(r.t, {t: r.t, sc: [], down: new Set()});
    const c = cycles.get(r.t);
    c.sc.push(scoreOf(r.status));
    if(r.status === 'CAIDA' || r.status === 'SIN RESPUESTA') c.down.add(r.name);
  }
  const pts = [...cycles.values()]
    .map(c => ({t: c.t, v: c.sc.reduce((a, b) => a + b, 0) / c.sc.length, down: [...c.down]}))
    .sort((a, b) => a.t < b.t ? -1 : 1);
  const pct = Math.round(svcs.reduce((a, s) => a + scoreOf(s.status), 0) / Math.max(1, svcs.length));
  const avg = pts.length ? Math.round(pts.reduce((a, p) => a + p.v, 0) / pts.length) : null;
  const minP = pts.reduce((m, p) => (!m || p.v < m.v ? p : m), null);
  const under = pts.filter(p => p.v < UMB.verde).length;
  const incs = [];
  svcs.forEach(s => (s.incidents || []).forEach(i => { if(i.start >= cut) incs.push({...i, name: s.name}); }));
  incs.sort((a, b) => a.start < b.start ? 1 : -1);
  const now = svcs.filter(s => s.status !== 'OK').map(s =>
    `<div><span class="dot" style="background:${stColor(s.status)}"></span><b>${esc(s.name)}</b> · ${esc(s.status)} · <span class="dmuted">${esc(s.target)}${s.error ? ' · ' + esc(s.error) : ''}</span></div>`).join('');
  const cnt = st => svcs.filter(s => s.status === st).length;
  const todayG = pts.filter(p => sameDay(p.t)).map(p => ({ms: tDate(p.t).getTime(), v: p.v, color: tierColor(p.v), title: shortT(p.t) + ' · ' + Math.round(p.v) + '% · ' + (p.down.length ? 'afectados: ' + p.down.join(', ') : 'todos OK')}));
  const chartHtml = dayChartBox('Estado general (%)', todayG, 100, '%');
  const tableRows = pts.slice().reverse().slice(0, 400).map(p => {
    const d = dtParts(p.t);
    return `<tr><td>${d.d}</td><td>${d.h}</td><td style="color:${tierColor(p.v)};font-weight:700">${Math.round(p.v)}%</td><td>${p.down.length ? esc(p.down.join(', ')) : '<span class="dmuted">ninguno</span>'}</td></tr>`;
  }).join('');
  const body = `
    <div class="dsum">
      <div class="dbig" style="color:${tierColor(pct)}">${pct}%</div>
      <div class="dmuted">
        OK ${cnt('OK')} · LENTO ${cnt('LENTO')} · AVISO ${cnt('AVISO')} · CAIDA ${cnt('CAIDA') + cnt('SIN RESPUESTA')} · de ${svcs.length} servicios
        ${HEALTH && HEALTH.maintenance ? '<br><b style="color:var(--media)">Ventana de mantenimiento activa: avisos silenciados</b>' : ''}</div>
    </div>
    ${chartHtml}
    ${spanBtns(dias)}
    <div class="dgrid">
      <div class="dbox"><b>${avg != null ? avg + '%' : '-'}</b><span>Media del periodo</span></div>
      <div class="dbox"><b>${minP ? Math.round(minP.v) + '%' : '-'}</b><span>Minimo ${minP ? dtParts(minP.t).d + ' ' + dtParts(minP.t).h : ''}</span></div>
      <div class="dbox"><b>${under} / ${pts.length}</b><span>Comprobaciones bajo el umbral verde</span></div>
      <div class="dbox"><b>${incs.length}</b><span>Incidencias en el periodo</span></div>
    </div>
    <div class="dsec"><h4>Servicios no OK ahora</h4>${now || '<div class="dmuted">Todos los servicios estan OK.</div>'}</div>
    <div class="dsec"><h4>Incidencias del periodo</h4>${incTable(incs)}</div>
    <div class="dsec"><h4>Detalle por comprobacion (fecha · hora · estado)</h4>
      <div class="dtab"><table><thead><tr><th>Fecha</th><th>Hora</th><th>Estado general</th><th>Servicios caidos</th></tr></thead><tbody>
      ${tableRows || '<tr><td colspan="4" class="dmuted">Sin datos en el periodo.</td></tr>'}</tbody></table></div>
    </div>`;
  showDetail('Estado general de salud', body);
}

async function openService(name, dias){
  dias = dias || DETAIL.dias || 1;
  DETAIL = {kind: 'svc', name, dias};
  const s = ((HEALTH && HEALTH.services) || []).find(x => x.name === name);
  if(!s) return;
  let rows = [];
  try { rows = await fetchRows(name, dias); } catch(e) {}
  rows.sort((a, b) => a.t < b.t ? 1 : -1);
  const u = s.uptime || {};
  const pc = v => v == null ? '-' : v + '%';
  const upN = rows.filter(r => r.status !== 'CAIDA' && r.status !== 'SIN RESPUESTA').length;
  const avail = rows.length ? (100 * upN / rows.length).toFixed(2) + '%' : '-';
  const avgMs = rows.length ? Math.round(rows.reduce((a, r) => a + r.ms, 0) / rows.length) + ' ms' : '-';
  const cut = cutoffStr(dias);
  const incs = (s.incidents || []).filter(i => i.start >= cut).map(i => ({...i, name: s.name}));
  const col = stColor(s.status);
  const todayS = rows.filter(r => sameDay(r.t)).map(r => ({ms: tDate(r.t).getTime(), v: r.ms, color: stColor(r.status), title: shortT(r.t) + ' · ' + s.name + ' · ' + r.status + ' · ' + r.ms + ' ms'})).sort((a, b) => a.ms - b.ms);
  const yMaxS = Math.max(100, Math.ceil(Math.max(100, ...todayS.map(p => p.v)) * 1.15 / 100) * 100);
  const chartHtml = dayChartBox('Tiempo de respuesta (ms)', todayS, yMaxS, ' ms');
  const tableRows = rows.slice(0, 500).map(r => {
    const d = dtParts(r.t);
    return `<tr><td>${d.d}</td><td>${d.h}</td><td style="color:${stColor(r.status)};font-weight:700">${esc(r.status)}</td><td>${r.ms} ms</td></tr>`;
  }).join('');
  const body = `
    <div class="dsum">
      <span class="hstate" style="color:${col};font-size:18px">${esc(s.status)}</span>
      <div class="dmuted"><b style="color:var(--txt);font-size:15px">${esc(s.name)}</b><br>
        ${s.kind === 'http' ? 'HTTP ' + (s.code || '-') : esc((s.kind || '').toUpperCase())} · ${s.ms} ms
        ${s.error ? '<br><span style="color:var(--crit)">' + esc(s.error) + '</span>' : ''}<br>
        URL analizada: <span style="word-break:break-all">${esc(s.target)}</span></div>
    </div>
    <div class="dgrid">
      <div class="dbox"><b>${pc(u.d1)}</b><span>Disponibilidad 24 h</span></div>
      <div class="dbox"><b>${pc(u.d7)}</b><span>Disponibilidad 7 dias</span></div>
      <div class="dbox"><b>${pc(u.d30)}</b><span>Disponibilidad 30 dias</span></div>
      <div class="dbox"><b>${s.avgMs != null ? s.avgMs + ' ms' : '-'}</b><span>Latencia media 24 h</span></div>
    </div>
    ${chartHtml}
    ${spanBtns(dias)}
    <div class="dgrid">
      <div class="dbox"><b>${avail}</b><span>Disponibilidad del periodo</span></div>
      <div class="dbox"><b>${avgMs}</b><span>Latencia media del periodo</span></div>
      <div class="dbox"><b>${rows.length}</b><span>Comprobaciones del periodo</span></div>
      <div class="dbox"><b>${incs.length}</b><span>Incidencias del periodo</span></div>
    </div>
    <div class="dsec"><h4>Incidencias del periodo</h4>${incTable(incs)}</div>
    <div class="dsec"><h4>Detalle (fecha · hora · estado)</h4>
      <div class="dtab"><table><thead><tr><th>Fecha</th><th>Hora</th><th>Estado</th><th>Tiempo de respuesta</th></tr></thead><tbody>
      ${tableRows || '<tr><td colspan="4" class="dmuted">Sin datos en el periodo.</td></tr>'}</tbody></table></div>
    </div>`;
  showDetail('Servicio: ' + s.name, body);
}

document.addEventListener('click', e => {
  const b = e.target.closest('.spanbtn');
  if(b && DETAIL.kind){
    const d = Number(b.dataset.dias);
    if(DETAIL.kind === 'gen') openGeneral(d); else openService(DETAIL.name, d);
    return;
  }
  if(e.target.closest('[data-gen]')){ openGeneral(DETAIL.dias); return; }
  const c = e.target.closest('[data-svc]');
  if(c){ openService(c.dataset.svc, DETAIL.dias); }
});
$('dClose').onclick = () => $('detailOverlay').classList.remove('show');
$('detailOverlay').onclick = ev => { if(ev.target.id === 'detailOverlay') $('detailOverlay').classList.remove('show'); };

/* ---- Avisos: ventana emergente, notificacion del sistema e icono de pestaña ---- */
// Los navegadores exigen un clic para pedir permiso de notificaciones
document.addEventListener('click', () => {
  if('Notification' in window && Notification.permission === 'default') Notification.requestPermission();
}, {once:true});

function notify(title, body){
  if('Notification' in window && Notification.permission === 'granted'){
    try{ new Notification(title, {body: body, tag: title}); }catch(e){}
  }
}
function setFavicon(href){
  let l = document.querySelector("link[rel='icon']");
  if(!l){ l = document.createElement('link'); l.rel = 'icon'; document.head.appendChild(l); }
  l.href = href;
}
// Prioridad: servicio caido (advertencia parpadeante) > noticia nueva (informacion) > normal
function updateFavicon(){
  clearInterval(blinkTimer); blinkTimer = null;
  if(ALARM_DOWN){
    let on = true; setFavicon(ICON_WARN);
    blinkTimer = setInterval(() => { on = !on; setFavicon(on ? ICON_WARN : ICON_SEARCH); }, 700);
  } else if(ALARM_NEWS){
    setFavicon(ICON_INFO);
  } else {
    setFavicon(ICON_SEARCH);
  }
}
function renderAlert(){
  if(!PENDING.length){ $('alertOverlay').classList.remove('show'); return; }
  $('alertTitle').textContent = 'Avisos (' + PENDING.length + ')';
  const hasOk = PENDING.some(a => a.tipo === 'ok');
  $('alertBody').innerHTML = PENDING.map(a => `<li class="${a.tipo}">${a.html}</li>`).join('') +
    (hasOk ? `<li class="cdl">Los avisos de recuperacion se cierran en ${OK_LEFT} s</li>` : '');
  $('alertOverlay').classList.add('show');
}
function addAlert(tipo, html){ PENDING.push({tipo, html}); renderAlert(); }
// Recuperacion: se cierra sola a los 10 segundos (cuenta atras visible)
let OK_LEFT = 0, okTimer = null;
function addRecovery(html){
  PENDING.push({tipo: 'ok', html});
  OK_LEFT = 10;
  renderAlert();
  clearInterval(okTimer);
  okTimer = setInterval(() => {
    OK_LEFT--;
    if(OK_LEFT <= 0){
      clearInterval(okTimer);
      PENDING = PENDING.filter(a => a.tipo !== 'ok');
    }
    renderAlert();
  }, 1000);
}
$('alertClose').onclick = () => {
  clearInterval(okTimer);
  PENDING = []; renderAlert();
  ALARM_NEWS = false; updateFavicon();   // las caidas siguen avisando en la pestaña hasta que se recuperen
};

// Caida nueva de un servicio: popup + notificacion (y parpadeo en la pestaña mientras siga caido)
let DOWN_SINCE = {};
function checkServices(){
  const svcs = (HEALTH && HEALTH.enabled) ? (HEALTH.services || []) : [];
  const quiet = !!(HEALTH && HEALTH.maintenance);   // en mantenimiento no hay avisos emergentes
  const down = svcs.filter(s => s.status === 'CAIDA' || s.status === 'SIN RESPUESTA');
  const names = new Set(down.map(s => s.name));
  const newly = down.filter(s => !PREV_DOWN.has(s.name));
  const recovered = [...PREV_DOWN].filter(n => !names.has(n));
  for(const s of newly){
    DOWN_SINCE[s.name] = Date.now();
    if(quiet) continue;
    addAlert('down', `<span class="up">${esc(s.status)}</span> · <b>${esc(s.name)}</b><br><span class="hmeta">${esc(s.target)}${s.error ? ' · ' + esc(s.error) : ''}</span>`);
    notify('Servicio caido: ' + s.name, s.target + (s.error ? ' · ' + s.error : ''));
    // Enviar notificacion por correo
    sendEventNotification('service_down', s.name, (s.target || 'sin URL') + (s.error ? ' · ' + s.error : ''));
  }
  for(const n of recovered){
    const mins = DOWN_SINCE[n] ? Math.round((Date.now() - DOWN_SINCE[n]) / 60000) : null;
    delete DOWN_SINCE[n];
    if(quiet) continue;
    addRecovery(`<span class="okt">RECUPERADO</span> · <b>${esc(n)}</b>${mins != null ? '<br><span class="hmeta">Caido unos ' + mins + ' min</span>' : ''}`);
    notify('Servicio recuperado: ' + n, '');
    // Enviar notificacion por correo
    sendEventNotification('service_up', n, mins != null ? 'Caido ' + mins + ' minutos' : 'Recuperado');
  }
  PREV_DOWN = names;
  ALARM_DOWN = names.size > 0;
  updateFavicon();
}

// Noticia nueva: aparece en esta recopilacion y no se habia visto antes. La primera vez
// solo se memoriza (no avisa de todo lo existente). Se guarda en el navegador.
function checkNews(){
  if(!DATA) return;
  const now = Date.now(), DAY = 864e5;
  let seen = null;
  try{ seen = JSON.parse(localStorage.getItem(SEEN_KEY) || 'null'); }catch(e){}
  const firstRun = !seen || typeof seen !== 'object';
  if(firstRun) seen = {};
  const fresh = [];
  for(const i of (DATA.items || [])){
    if(!seen[i.url]){ seen[i.url] = now; if(!firstRun) fresh.push(i); }
  }
  for(const k of Object.keys(seen)) if(now - seen[k] > 7 * DAY) delete seen[k];
  try{ localStorage.setItem(SEEN_KEY, JSON.stringify(seen)); }catch(e){}
  if(fresh.length){
    ALARM_NEWS = true;
    addAlert('news', `<b>${fresh.length} noticia(s) nueva(s)</b><br>` + fresh.slice(0, 5).map(i =>
      `<a href="${esc(i.url)}" target="_blank" rel="noopener">${esc(i.title)}</a>`).join('<br>'));
    notify('ATALAYA: ' + fresh.length + ' noticia(s) nueva(s)', fresh[0].title);
    // Enviar notificacion por correo con las noticias nuevas
    sendEventNotification('news', 'Noticias nuevas', fresh[0].title, {count: fresh.length, titles: fresh.slice(0, 10).map(i => i.title)});
  }
  updateFavicon();
}
loadHealth(false);
setInterval(() => loadHealth(false), 30000);

(async () => {
  try{
    const s = await getSettings();
    UMB = {verde: s.config.salud_umbral_verde || 90, ambar: s.config.salud_umbral_ambar || 60};
    applyLayout(s.config);
    PANEL_VIEW = null;
    ACTIVE_SEVS = s.config.severidades;
    applyTheme(s.config.tema);
    applyFont(s.config.tamano_letra);
    renderToggles();
  }catch(e){}
  load(false);
  // Refresca la vista cada 10 min; el servidor solo recopila de nuevo cada noticias_intervalo_min
  setInterval(() => load(false), 600000);
})();

/* ---- Estado de ATALAYA y estadisticas con graficas sencillas ---- */
const ESTADO_COLORES = {OK:'#2e8b57', LENTO:'#b07d06', AVISO:'#b07d06', CAIDA:'#b3261e', 'SIN RESPUESTA':'#b3261e', Critica:'#b3261e', Grave:'#d4621f', Media:'#b07d06', Baja:'#3c6ea8', Info:'#6b7585'};
// Barras horizontales: items = [{label, value, color}]
function barrasH(items, max){
  if(!items.length) return '<div class="dmuted">Sin datos.</div>';
  const m = max || Math.max(1, ...items.map(i => i.value));
  return '<div style="display:grid;gap:6px">' + items.map(i => `
    <div style="display:grid;grid-template-columns:minmax(90px,30%) 1fr 48px;gap:8px;align-items:center;font-size:12px">
      <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${esc(i.label)}">${esc(i.label)}</span>
      <span style="background:var(--panel2);border-radius:6px;height:12px;overflow:hidden"><span style="display:block;height:100%;width:${Math.round(100*i.value/m)}%;background:${i.color || 'var(--acc)'};border-radius:6px"></span></span>
      <b style="text-align:right;font-variant-numeric:tabular-nums">${i.value}</b>
    </div>`).join('') + '</div>';
}
// Columnas verticales (p. ej. 24 horas): items = [{label, value}]
function columnas(items, color){
  const m = Math.max(1, ...items.map(i => i.value));
  const w = 100 / items.length;
  const bars = items.map((i, k) => {
    const hgt = Math.round(100 * i.value / m);
    return `<div title="${esc(i.label)}: ${i.value}" style="position:absolute;left:${k*w}%;bottom:0;width:${w*0.7}%;height:${hgt}%;background:${i.color || color || 'var(--acc)'};border-radius:3px 3px 0 0"></div>`;
  }).join('');
  const etiq = items.filter((_, k) => k % 3 === 0).map(i => `<span>${esc(i.label)}</span>`).join('');
  return `<div style="position:relative;height:90px;border-bottom:1px solid var(--line2)">${bars}</div><div style="display:flex;justify-content:space-between;font-size:10px;color:var(--mut);margin-top:3px">${etiq}</div>`;
}
// Barra de estados (proporcion de cada estado)
function barraApilada(items){
  const tot = items.reduce((a, i) => a + i.value, 0);
  if(!tot) return '<div class="dmuted">Sin comprobaciones en las ultimas 24 h.</div>';
  return '<div style="display:flex;height:18px;border-radius:9px;overflow:hidden">' + items.map(i => `<span title="${esc(i.label)}: ${i.value} (${Math.round(100*i.value/tot)}%)" style="flex:${i.value};background:${i.color}"></span>`).join('') + '</div>' +
    '<div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:6px;font-size:12px">' + items.map(i => `<span><i style="display:inline-block;width:9px;height:9px;border-radius:50%;background:${i.color};margin-right:5px"></i>${esc(i.label)}: <b>${i.value}</b> (${Math.round(100*i.value/tot)}%)</span>`).join('') + '</div>';
}
function tarjeta(titulo, valor, ayuda, ok){
  const c = ok === undefined ? 'var(--txt)' : (ok ? '#2e8b57' : '#b3261e');
  return `<div class="dbox"><b style="color:${c}">${valor}</b><span>${esc(titulo)}</span>${ayuda ? `<div class="dmuted" style="font-size:10.5px">${esc(ayuda)}</div>` : ''}</div>`;
}

async function openEstado(){
  let e;
  try { e = await (await fetch('/api/estado')).json(); }
  catch(err){ showDetail('Estado ATALAYA', '<div class="empty">No se pudo leer el estado del servidor.</div>'); return; }
  const s = e.sistema, a = e.analisis;
  const monOk = s.monitorProcesos === 1;
  const sistema = `
    <div class="dgrid">
      ${tarjeta('Monitor de servicios', s.monitorProcesos === 1 ? 'Activo' : (s.monitorProcesos === 0 ? 'Parado' : s.monitorProcesos + ' procesos'), s.monitorProcesos === 1 ? 'Un solo proceso' : 'Revisar: debe haber exactamente uno', monOk)}
      ${tarjeta('Ultima comprobacion', s.monitorGenerado || '-', 'Cada ' + Math.round((s.monitorIntervaloSeg || 0) / 60) + ' min')}
      ${tarjeta('Puerto', s.puerto, 'Pagina en http://localhost:' + s.puerto + '/')}
      ${tarjeta('Mantenimiento', s.monitorMantenimiento ? 'Si' : 'No', 'Avisos silenciados si esta activo')}
      ${tarjeta('Noticias archivadas', s.archivoNoticias, 'Archivo.jsonl')}
      ${tarjeta('Historico', s.historicoLineas, s.historicoMB + ' MB')}
    </div>`;
  const comp = a.comprobaciones24h.map(c => ({label: c.estado, value: c.n, color: ESTADO_COLORES[c.estado] || 'var(--acc)'}));
  const horas = (a.porHora || []).map((n, k) => ({label: String(k).padStart(2,'0') + ':00', value: n}));
  const caidasH = (a.porHoraCaida || []).map((n, k) => ({label: String(k).padStart(2,'0') + ':00', value: n, color: '#b3261e'}));
  const svcs = a.servicios.map(v => ({label: v.name, value: v.d7 == null ? 0 : v.d7, color: v.status === 'OK' ? '#2e8b57' : '#b3261e'}));
  const sev = Object.entries(a.archivoPorSeveridad).map(([k, v]) => ({label: k, value: v, color: ESTADO_COLORES[k]}));
  const fuentes = a.archivoPorFuente.sort((x, y) => y.n - x.n).map(f => ({label: f.fuente, value: f.n}));
  const temas = a.archivoPorTema.sort((x, y) => y.n - x.n).slice(0, 12).map(t => ({label: t.tema, value: t.n}));
  const meses = a.archivoPorMes.map(m => ({label: m.mes, value: m.n}));
  const estadisticas = `
    <div class="dgrid">
      ${tarjeta('Noticias en el informe actual', a.noticiasActuales)}
      ${tarjeta('Noticias archivadas', s.archivoNoticias)}
      ${tarjeta('Servicios', a.servicios.length, a.servicios.filter(v => v.status === 'OK').length + ' OK ahora')}
      ${tarjeta('Incidencias (30 dias)', a.servicios.reduce((n, v) => n + v.incidencias30, 0))}
    </div>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Comprobaciones de las ultimas 24 h</legend>${barraApilada(comp)}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Comprobaciones por hora (ultimas 24 h)</legend>${columnas(horas, 'var(--acc)')}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Caidas por hora (ultimas 24 h)</legend>${columnas(caidasH)}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Disponibilidad de cada servicio (7 dias, %)</legend>${barrasH(svcs, 100)}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Noticias archivadas por severidad</legend>${barrasH(sev)}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Noticias archivadas por fuente</legend>${barrasH(fuentes)}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Noticias por tema (top 12)</legend>${barrasH(temas)}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Noticias archivadas por mes</legend>${columnas(meses, 'var(--acc2)')}</fieldset>`;
  showDetail('Estado ATALAYA', `
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Estado del sistema</legend>${sistema}</fieldset>
    <fieldset class="dsec" style="border:1px solid var(--line2);border-radius:10px;padding:12px"><legend class="dmuted">Estadisticas generales</legend>${estadisticas}</fieldset>`);
}
$('btnEstado').onclick = openEstado;
// Pestañas del panel derecho
document.querySelectorAll('.ptab').forEach(el => el.onclick = () => { PANEL_VIEW = el.dataset.tab; renderTopics(); });

// Monitor de salud: minimizar / maximizar (el valor inicial sale de config: monitor_vista)
// Se puede pulsar tanto la flecha como el propio titulo: todo el boton es clicable.
function applyMon(){
  const b = $('healthBody');
  if(b) b.classList.toggle('hidden', MON_MIN);
  const c = $('monChev');
  if(c) c.classList.toggle('collapsed', MON_MIN);
}
$('btnMon').onclick = () => { MON_MIN = !MON_MIN; applyMon(); };







