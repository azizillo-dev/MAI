/* Mentor AI — taqdimot sayti. Kutubxonasiz; KaTeX va qrcode-generator ixtiyoriy (CDN). */
(() => {
  'use strict';

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const API = (window.MENTOR_API || '/api/v1').replace(/\/$/, '');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const finePointer = matchMedia('(hover: hover) and (pointer: fine)').matches;

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sum = (n) => Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const som = (n) => `${sum(n)} so‘m`;
  const big = (n) => {
    const a = Math.abs(n);
    if (a >= 1e9) return `${(n / 1e9).toFixed(2).replace('.', ',')} mlrd so‘m`;
    if (a >= 1e6) return `${(n / 1e6).toFixed(1).replace('.', ',')} mln so‘m`;
    return som(n);
  };
  const pct = (x) => `${Math.round(x * 100)}%`;
  const store = {
    get(k) { try { return JSON.parse(sessionStorage.getItem(k)); } catch { return null; } },
    set(k, v) { try { sessionStorage.setItem(k, JSON.stringify(v)); } catch { /* shaxsiy rejim */ } },
    del(k) { try { sessionStorage.removeItem(k); } catch { /* shaxsiy rejim */ } },
  };

  document.documentElement.classList.remove('no-js');
  $('#year').textContent = new Date().getFullYear();

  // ---------------------------------------------------------------- Ma'lumotlar (API, zaxira bilan)
  const FALLBACK = {
    plans: [
      { code: 'standard', name: 'Standart', price_uzs: 149000, max_groups: 1, max_students: 30, max_assignments_per_week: null },
      { code: 'pro', name: 'Pro', price_uzs: 399000, max_groups: 3, max_students: 90, max_assignments_per_week: null },
    ],
    trial: { code: 'trial', name: 'Sinov (14 kun)', price_uzs: 0, max_groups: 1, max_students: 30 },
    stats: null,
    downloads: {
      version: '1.1.1', arm64_url: '/downloads/MentorAI-arm64.apk', legacy_url: '/downloads/MentorAI-eski-telefonlar.apk',
      arm64_size_mb: 30, legacy_size_mb: 26, note: 'Android 7.0 va undan yuqori',
    },
    secret_enabled: true,
  };

  async function api(path, opts = {}) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), opts.timeout || 8000);
    try {
      const res = await fetch(API + path, {
        ...opts, signal: ctrl.signal,
        headers: { 'Content-Type': 'application/json', ...(opts.headers || {}) },
      });
      const body = await res.json().catch(() => null);
      if (!res.ok) throw Object.assign(new Error(body?.error?.message || body?.detail || res.statusText), { status: res.status });
      return body;
    } finally { clearTimeout(t); }
  }

  // ---------------------------------------------------------------- Navigatsiya
  const nav = $('#nav');
  const burger = $('#burger');
  const onScroll = () => nav.classList.toggle('is-scrolled', scrollY > 8);
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();
  const setMenu = (open) => {
    nav.classList.toggle('is-open', open);
    burger.setAttribute('aria-expanded', String(open));
    burger.setAttribute('aria-label', open ? 'Menyuni yopish' : 'Menyuni ochish');
  };
  burger.addEventListener('click', () => setMenu(!nav.classList.contains('is-open')));
  $$('#navLinks a').forEach((a) => a.addEventListener('click', () => setMenu(false)));
  addEventListener('keydown', (e) => { if (e.key === 'Escape') setMenu(false); });

  const navMap = new Map($$('#navLinks a').map((a) => [a.getAttribute('href').slice(1), a]));
  const sectionIO = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting) return;
      navMap.forEach((a) => a.classList.remove('is-current'));
      navMap.get(en.target.id)?.classList.add('is-current');
    });
  }, { rootMargin: '-45% 0px -50% 0px' });
  navMap.forEach((_, id) => { const s = document.getElementById(id); if (s) sectionIO.observe(s); });

  // ---------------------------------------------------------------- Paydo bo'lish va hisoblagichlar
  const groups = new Map();
  $$('.reveal').forEach((el) => {
    const p = el.parentElement;
    const i = groups.get(p) || 0;
    groups.set(p, i + 1);
    if (i) el.style.setProperty('--d', `${Math.min(i, 6) * 0.07}s`);
  });
  const revealIO = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting) return;
      en.target.classList.add('is-visible');
      revealIO.unobserve(en.target);
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
  $$('.reveal, .card').forEach((el) => revealIO.observe(el));

  const countIO = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting) return;
      countIO.unobserve(en.target);
      const el = en.target;
      const to = +el.dataset.count;
      if (reduceMotion) { el.textContent = sum(to); return; }
      const t0 = performance.now();
      const dur = 1400;
      const tick = (t) => {
        const k = Math.min(1, (t - t0) / dur);
        el.textContent = sum(to * (1 - Math.pow(1 - k, 3)));
        if (k < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
  }, { threshold: 0.6 });
  $$('[data-count]').forEach((el) => { el.textContent = '0'; countIO.observe(el); });

  // ---------------------------------------------------------------- Kartalar ustidagi yorug'lik
  if (finePointer) {
    $$('.card').forEach((c) => c.addEventListener('pointermove', (e) => {
      const r = c.getBoundingClientRect();
      c.style.setProperty('--mx', `${e.clientX - r.left}px`);
      c.style.setProperty('--my', `${e.clientY - r.top}px`);
    }));
  }

  // ---------------------------------------------------------------- Hero parallaks
  const stage = $('#heroStage');
  if (stage && finePointer && !reduceMotion) {
    const items = $$('[data-depth]', stage).map((el) => ({ el, d: +el.dataset.depth, side: el.classList.contains('phone--side') }));
    let tx = 0, ty = 0, cx = 0, cy = 0, raf = 0;
    const loop = () => {
      cx += (tx - cx) * 0.08;
      cy += (ty - cy) * 0.08;
      items.forEach(({ el, d, side }) => {
        const x = (cx * d * 14).toFixed(2), y = (cy * d * 10).toFixed(2);
        if (side) el.style.translate = `${x}px ${y}px`;
        else el.style.transform = `translate3d(${x}px, ${y}px, 0)`;
      });
      raf = Math.abs(tx - cx) + Math.abs(ty - cy) > 0.001 ? requestAnimationFrame(loop) : 0;
    };
    $('.hero').addEventListener('pointermove', (e) => {
      tx = (e.clientX / innerWidth) * 2 - 1;
      ty = (e.clientY / innerHeight) * 2 - 1;
      if (!raf) raf = requestAnimationFrame(loop);
    });
  }

  // ---------------------------------------------------------------- LaTeX
  function renderTex(root = document) {
    $$('.tex[data-tex]', root).forEach((el) => {
      if (el.dataset.done) return;
      if (window.katex) {
        try { katex.render(el.dataset.tex, el, { throwOnError: false }); el.dataset.done = '1'; return; } catch { /* matn qoladi */ }
      }
      if (!el.textContent.trim()) el.textContent = el.dataset.tex.replace(/\\[a-z]+|[{}]/gi, ' ').replace(/\s+/g, ' ');
    });
  }
  renderTex();

  // ---------------------------------------------------------------- Showcase: ekranni almashtirish
  $$('[data-showcase]').forEach((sec) => {
    const shots = $$('.shot', sec);
    const screens = $$('.phone--show img', sec);
    const activate = (i) => {
      shots.forEach((s, k) => s.classList.toggle('is-active', k === i));
      screens.forEach((s, k) => s.classList.toggle('is-active', k === i));
    };
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => { if (en.isIntersecting) activate(+en.target.dataset.shot); });
    }, { rootMargin: '-48% 0px -48% 0px' });
    shots.forEach((s) => {
      io.observe(s);
      s.addEventListener('click', () => s.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'center' }));
    });
    // Birinchi ko'rsatishda keyingi rasmlar tayyor tursin
    new IntersectionObserver((en, o) => {
      if (en[0].isIntersecting) { screens.forEach((img) => { img.loading = 'eager'; }); o.disconnect(); }
    }, { rootMargin: '600px 0px' }).observe(sec);
  });

  // ---------------------------------------------------------------- AI generator demo
  const gen = $('#genDemo');
  if (gen) {
    const prompt = $('#genPrompt');
    const meta = $('#genMeta');
    const items = $$('#genItems li');
    const text = prompt.dataset.text;
    let timers = [];
    const later = (fn, ms) => timers.push(setTimeout(fn, ms));
    const reset = () => {
      timers.forEach(clearTimeout); timers = [];
      prompt.textContent = ''; meta.classList.remove('is-on'); gen.classList.remove('is-done');
      items.forEach((li) => li.classList.remove('is-on'));
    };
    const run = () => {
      reset();
      if (reduceMotion) {
        prompt.textContent = text; meta.classList.add('is-on'); gen.classList.add('is-done');
        items.forEach((li) => li.classList.add('is-on'));
        return;
      }
      let i = 0;
      const type = () => {
        prompt.textContent = text.slice(0, ++i);
        if (i < text.length) later(type, 26 + Math.random() * 30);
        else {
          later(() => meta.classList.add('is-on'), 350);
          items.forEach((li, k) => later(() => li.classList.add('is-on'), 900 + k * 260));
          later(() => gen.classList.add('is-done'), 900 + items.length * 260);
        }
      };
      later(type, 300);
    };
    new IntersectionObserver((en, o) => { if (en[0].isIntersecting) { run(); o.disconnect(); } }, { threshold: 0.4 }).observe(gen);
    $('#genReplay').addEventListener('click', run);
    $('#genAnswers').addEventListener('change', (e) => gen.classList.toggle('no-answers', !e.target.checked));
  }

  // ---------------------------------------------------------------- Jetonlar
  const JETONS = [
    { name: 'Sinf yulduzi', icon: 'star', tier: 'gold', price: 12000 },
    { name: 'Oltin qalam', icon: 'pen', tier: 'gold', price: 6000 },
    { name: 'Aql chirog‘i', icon: 'bulb', tier: 'purple', price: 8000 },
    { name: 'Tirishqoq', icon: 'rocket', tier: 'blue', price: 6000 },
    { name: 'Yosh matematik', icon: 'calc', tier: 'green', price: 8000 },
    { name: 'So‘z ustasi', icon: 'lang', tier: 'green', price: 8000 },
    { name: 'Ustoz mehri', icon: 'heart', tier: 'silver', price: 4000 },
    { name: 'Chempion', icon: 'medal', tier: 'gold', price: 20000 },
  ];
  const hex = (tier, icon) => `
    <svg class="hex" viewBox="0 0 100 110" aria-hidden="true">
      <polygon points="50,6 92,30 92,80 50,104 8,80 8,30" fill="url(#g-${tier})" stroke="url(#g-${tier})" stroke-width="8" stroke-linejoin="round"/>
      <polygon points="50,17 82,35.5 82,74.5 50,93 18,74.5 18,35.5" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="1.6" stroke-linejoin="round"/>
      <path d="M8 30 50 6 92 30v12Q50 30 8 50Z" fill="rgba(255,255,255,.2)"/>
      <use href="#i-${icon}" x="32" y="37" width="36" height="36" fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;
  const jg = $('#jetonGrid');
  if (jg) {
    jg.innerHTML = JETONS.map((j) => `<div class="jeton reveal">${hex(j.tier, j.icon)}<b>${esc(j.name)}</b><small>${som(j.price)}</small></div>`).join('');
    $$('.jeton', jg).forEach((el, i) => { el.style.setProperty('--d', `${i * 0.05}s`); revealIO.observe(el); });
  }

  // ---------------------------------------------------------------- Narxlar
  const PLAN_COPY = {
    trial: { desc: 'Ilovani hech qanday to‘lovsiz sinab ko‘ring', cta: 'Bepul boshlash' },
    standard: { desc: 'Bitta sinf bilan ishlaydigan o‘qituvchi uchun', cta: 'Standartni tanlash' },
    pro: { desc: 'Bir nechta sinfga dars beradigan o‘qituvchi uchun', cta: 'Pro’ni tanlash', badge: 'Eng foydali' },
  };
  const tick = (t) => `<li><svg class="ic"><use href="#i-check"/></svg>${t}</li>`;
  function renderPricing(info) {
    const list = [info.trial, ...info.plans].filter(Boolean);
    $('#pricing').innerHTML = list.map((p) => {
      const copy = PLAN_COPY[p.code] || { desc: '', cta: 'Tanlash' };
      const hot = p.code === 'pro';
      const isTrial = p.code === 'trial';
      const feats = [
        `${p.max_groups} ta guruh`,
        `${p.max_students} tagacha o‘quvchi`,
        p.max_assignments_per_week ? `Haftasiga ${p.max_assignments_per_week} ta vazifa` : 'Vazifalar soni cheklanmagan',
        'AI tekshiruv, AI generator va yordamchi',
        'Guruh tahlili, PDF va Excel hisobot',
        isTrial ? 'Karta talab qilinmaydi' : 'Ustoz jetonlarini sotib olish',
      ];
      const per = isTrial ? '14 kun davomida' : `o‘quvchi boshiga ~${sum(Math.round(p.price_uzs / p.max_students / 100) * 100)} so‘m/oy`;
      return `
        <article class="plan${hot ? ' plan--hot' : ''} reveal">
          ${copy.badge ? `<span class="plan__badge">${copy.badge}</span>` : ''}
          <h3>${esc(isTrial ? 'Sinov' : p.name)}</h3>
          <p class="plan__desc">${copy.desc}</p>
          <p class="plan__price"><b>${isTrial ? '0' : sum(p.price_uzs)}</b><span>so‘m${isTrial ? '' : ' / oy'}</span></p>
          <p class="plan__per">${per}</p>
          <ul>${feats.map(tick).join('')}</ul>
          <a class="btn ${hot ? 'btn--primary' : 'btn--ghost'} btn--lg" href="#yuklash">${copy.cta}</a>
        </article>`;
    }).join('');
    $$('#pricing .reveal').forEach((el, i) => { el.style.setProperty('--d', `${i * 0.08}s`); revealIO.observe(el); });
  }

  // ---------------------------------------------------------------- Yuklab olish va QR
  function qrSvg(text) {
    const q = qrcode(0, 'M');
    q.addData(text);
    q.make();
    const n = q.getModuleCount();
    const finder = (r, c) => (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
    let d = '';
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (q.isDark(r, c) && !finder(r, c)) d += `M${c} ${r}h1v1h-1z`;
    const eye = (x, y) => `<rect x="${x + 0.5}" y="${y + 0.5}" width="6" height="6" rx="1.7" fill="none" stroke="#1e1b4b" stroke-width="1"/><rect x="${x + 2}" y="${y + 2}" width="3" height="3" rx=".9" fill="#4f46e5"/>`;
    return `<svg viewBox="0 0 ${n} ${n}" shape-rendering="crispEdges" role="img"><path d="${d}" fill="#0f0f2a"/><g shape-rendering="geometricPrecision">${eye(0, 0)}${eye(n - 7, 0)}${eye(0, n - 7)}</g></svg>`;
  }
  function renderDownloads(dl) {
    const vals = {
      arm64Url: dl.arm64_url, legacyUrl: dl.legacy_url, version: dl.version, note: dl.note,
      arm64Size: `${dl.arm64_size_mb} MB`, legacySize: `${dl.legacy_size_mb} MB`,
    };
    $$('[data-bind]').forEach((el) => { if (vals[el.dataset.bind] != null) el.textContent = vals[el.dataset.bind]; });
    $$('[data-bind-href]').forEach((el) => { if (vals[el.dataset.bindHref]) el.href = vals[el.dataset.bindHref]; });
    $$('[data-qr]').forEach((el) => {
      const url = vals[el.dataset.qr];
      if (!url || !window.qrcode) { el.hidden = true; return; }
      try { el.innerHTML = qrSvg(new URL(url, location.href).href); } catch { el.hidden = true; }
    });
  }

  // ---------------------------------------------------------------- Yopiq bo'lim
  const SECRET_KEY = 'mentor_secret_v1';
  const lock = $('#secretLock');
  const body = $('#secretBody');
  const form = $('#secretForm');
  const err = $('#secretError');
  let secret = null;
  let state = null;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = $('#secretBtn');
    const pw = $('#secretPassword').value;
    if (!pw) return;
    btn.disabled = true;
    err.textContent = '';
    try {
      const data = await api('/site/secret', { method: 'POST', body: JSON.stringify({ password: pw }), timeout: 12000 });
      store.set(SECRET_KEY, data);
      $('#secretPassword').value = '';
      openSecret(data);
    } catch (ex) {
      err.textContent = ex.status === 401 ? 'Parol noto‘g‘ri' : ex.status === 429 ? 'Juda ko‘p urinish. Birozdan so‘ng qayta urining' : 'Server bilan aloqa yo‘q. Keyinroq urinib ko‘ring';
      form.classList.remove('shake'); void form.offsetWidth; form.classList.add('shake');
    } finally { btn.disabled = false; }
  });
  $('#secretClose').addEventListener('click', () => {
    store.del(SECRET_KEY);
    secret = null;
    body.hidden = true;
    lock.hidden = false;
    lock.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'center' });
  });

  function openSecret(data) {
    secret = data;
    const e = data.economics;
    const paid = data.plans.filter((p) => p.code !== 'trial' && p.price_uzs > 0);
    if (!paid.length) return;
    state = {
      plan: paid.find((p) => p.code === 'standard') || paid[0],
      mode: 'now',
      students: 0,
      weekly: Math.round(e.assignments_per_week),
      submit: Math.round(e.submit_rate * 100),
      teachers: Math.round(e.paying_teachers),
    };
    state.students = state.plan.max_students;
    lock.hidden = true;
    body.hidden = false;

    const planSeg = $('#calcPlan');
    planSeg.innerHTML = paid.map((p) => `<button type="button" role="radio" aria-checked="${p === state.plan}" data-code="${esc(p.code)}">${esc(p.name)}</button>`).join('');
    planSeg.onclick = (ev) => {
      const b = ev.target.closest('button'); if (!b) return;
      state.plan = paid.find((p) => p.code === b.dataset.code);
      state.students = state.plan.max_students;
      $$('button', planSeg).forEach((x) => x.setAttribute('aria-checked', String(x === b)));
      syncSliders(); update();
    };
    const modeSeg = $('#calcMode');
    modeSeg.onclick = (ev) => {
      const b = ev.target.closest('button'); if (!b) return;
      state.mode = b.dataset.v;
      $$('button', modeSeg).forEach((x) => x.setAttribute('aria-checked', String(x === b)));
      update();
    };
    $$('button', modeSeg).forEach((x) => x.setAttribute('aria-checked', String(x.dataset.v === 'now')));

    const bindRange = (id, key) => {
      const el = $(id);
      el.oninput = () => { state[key] = +el.value; update(); };
    };
    bindRange('#calcStudents', 'students');
    bindRange('#calcWeekly', 'weekly');
    bindRange('#calcSubmit', 'submit');
    bindRange('#calcTeachers', 'teachers');
    syncSliders();
    renderScenarios();
    renderAssumptions();
    update();
  }

  function syncSliders() {
    const s = $('#calcStudents');
    s.max = state.plan.max_students;
    s.value = state.students;
    $('#calcWeekly').value = state.weekly;
    $('#calcSubmit').value = state.submit;
    const t = $('#calcTeachers');
    t.max = Math.max(2000, state.teachers);
    t.value = state.teachers;
  }

  /** Bir o'qituvchining oylik iqtisodiyoti (so'mda). */
  function model(e, plan, o) {
    const later = o.mode === '2027';
    const pin = later ? e.price_in_2027 : e.price_in;
    const pout = later ? e.price_out_2027 : e.price_out;
    const usd = e.usd_uzs;
    const oh = 1 + e.overhead;
    const gradeUsd = (e.grade_in_tokens * pin + e.grade_out_tokens * pout) / 1e6;
    const prepUsd = (e.prepare_in_tokens * pin + e.prepare_out_tokens * pout) / 1e6;
    const asstUsd = e.assistant_calls_per_month * (e.assistant_in_tokens * pin + e.assistant_out_tokens * pout) / 1e6;
    const perGroup = Math.max(1, plan.max_students / Math.max(1, plan.max_groups));
    const groups = Math.min(plan.max_groups, Math.max(1, Math.ceil(o.students / perGroup)));
    const weeksPerMonth = 52 / 12;
    const tasks = o.weekly * weeksPerMonth * groups;
    const grades = o.weekly * weeksPerMonth * o.students * o.submit * (1 + e.resubmit_rate);
    const aiGrade = grades * gradeUsd * oh * usd;
    const aiOther = (tasks * prepUsd + asstUsd) * oh * usd;
    const server = (e.server_usd_month / Math.max(1, o.teachers)) * usd;
    const price = plan.price_uzs;
    const fee = price * e.payment_fee;
    const cost = aiGrade + aiOther + server + fee;
    return {
      price, aiGrade, aiOther, server, fee, cost, grades, tasks,
      profit: price - cost, margin: price ? (price - cost) / price : 0,
      unitGrade: gradeUsd * usd, unitGradeUsd: gradeUsd, unitPrep: prepUsd * usd, unitAsst: asstUsd * usd,
    };
  }

  const SEG = [
    { key: 'aiGrade', label: 'AI tekshiruv', color: '#6366f1' },
    { key: 'aiOther', label: 'Vazifa tayyorlash va yordamchi', color: '#38bdf8' },
    { key: 'server', label: 'Server ulushi', color: '#f472b6' },
    { key: 'fee', label: 'To‘lov komissiyasi', color: '#fbbf24' },
    { key: 'profit', label: 'Sof foyda', color: '#34d399' },
  ];

  function update() {
    const e = secret.economics;
    const o = { ...state, submit: state.submit / 100 };
    const r = model(e, state.plan, o);

    const fill = (el) => el.style.setProperty('--fill', `${((el.value - el.min) / (el.max - el.min)) * 100}%`);
    $$('.calc input[type=range]').forEach(fill);
    $('#oStudents').textContent = `${state.students} ta`;
    $('#oWeekly').textContent = `${state.weekly} ta`;
    $('#oSubmit').textContent = `${state.submit}%`;
    $('#oTeachers').textContent = sum(state.teachers);

    $('#unitKpis').innerHTML = [
      ['1 ta daftarni tekshirish', som(r.unitGrade), `$${r.unitGradeUsd.toFixed(4)} · ${sum(e.grade_in_tokens + e.grade_out_tokens)} token`],
      ['1 vazifani AI tayyorlashi', som(r.unitPrep), 'javoblar va misollar tahlili'],
      ['AI yordamchi / oy', som(r.unitAsst), `${sum(e.assistant_calls_per_month)} ta so‘rov`],
      ['Oyiga tekshiruvlar', sum(r.grades), `${state.plan.name}: ${state.students} o‘quvchi`],
    ].map(([k, v, s]) => `<div class="kpi"><small>${k}</small><b>${v}</b><span>${esc(s)}</span></div>`).join('');

    const pEl = $('#rProfit');
    pEl.textContent = som(r.profit);
    pEl.classList.toggle('is-neg', r.profit < 0);
    $('#rMargin').textContent = `Marja ${pct(r.margin)} · narx ${som(r.price)} · xarajat ${som(r.cost)}`;

    const total = Math.max(r.price, r.cost) || 1;
    const vals = { ...r, profit: Math.max(0, r.profit) };
    const split = $('#rSplit');
    split.innerHTML = SEG.map((s) => `<i style="width:${(vals[s.key] / total) * 100}%;background:${s.color}" title="${s.label}: ${som(vals[s.key])}"></i>`).join('');
    split.setAttribute('aria-label', SEG.map((s) => `${s.label} ${som(vals[s.key])}`).join(', '));
    $('#rLegend').innerHTML = SEG.map((s) => `<li><i style="background:${s.color}"></i>${s.label}<b>${som(s.key === 'profit' ? r.profit : r[s.key])}</b></li>`).join('');

    const n = state.teachers;
    $('#rTotals').innerHTML = `
      <div><small>Oylik tushum</small><b>${big(r.price * n)}</b></div>
      <div><small>Oylik xarajat</small><b>${big(r.cost * n)}</b></div>
      <div><small>Oylik sof foyda</small><b class="${r.profit >= 0 ? 'pos' : 'neg'}">${big(r.profit * n)}</b></div>
      <p>${sum(n)} ta to‘lovchi o‘qituvchi, hammasi “${esc(state.plan.name)}” tarifida. Yillik foyda: ${big(r.profit * n * 12)}.</p>`;
  }

  function renderScenarios() {
    const e = secret.economics;
    const base = { weekly: e.assignments_per_week, submit: e.submit_rate, teachers: e.paying_teachers };
    const rows = secret.plans.map((p) => {
      const isTrial = p.code === 'trial' || p.price_uzs === 0;
      const o = { ...base, students: p.max_students };
      const now = model(e, p, { ...o, mode: 'now' });
      const later = model(e, p, { ...o, mode: '2027' });
      const k = isTrial ? 14 / 30 : 1; // sinov davri 14 kun
      const cell = (x) => (isTrial
        ? `<td>${som(x.cost * k)}</td><td class="neg">−${som(x.cost * k)}</td><td><small>—</small></td>`
        : `<td>${som(x.cost)}</td><td class="${x.profit >= 0 ? 'pos' : 'neg'}">${som(x.profit)}</td><td>${pct(x.margin)}</td>`);
      return `<tr><td><b>${esc(p.name)}</b><br><small>${p.max_students} o‘quvchi · ${p.max_groups} guruh</small></td><td>${isTrial ? '<small>bepul</small>' : som(p.price_uzs)}</td>${cell(now)}${cell(later)}</tr>`;
    }).join('');
    $('#scenTable').innerHTML = `
      <thead><tr><th>Tarif</th><th>Narx / oy</th><th>Xarajat</th><th>Foyda</th><th>Marja</th><th>Xarajat 2027</th><th>Foyda 2027</th><th>Marja 2027</th></tr></thead>
      <tbody>${rows}</tbody>`;
  }

  function renderAssumptions() {
    const e = secret.economics;
    const items = [
      ['AI model', e.model],
      ['Dollar kursi', som(e.usd_uzs)],
      ['Kirish tokeni (1 mln)', `$${e.price_in} → $${e.price_in_2027}`],
      ['Chiqish tokeni (1 mln)', `$${e.price_out} → $${e.price_out_2027}`],
      ['1 tekshiruv', `${sum(e.grade_in_tokens)} + ${sum(e.grade_out_tokens)} token`],
      ['1 vazifa tayyorlash', `${sum(e.prepare_in_tokens)} + ${sum(e.prepare_out_tokens)} token`],
      ['AI yordamchi', `${e.assistant_calls_per_month} × (${sum(e.assistant_in_tokens)} + ${sum(e.assistant_out_tokens)})`],
      ['Haftasiga vazifa', `${e.assignments_per_week} ta / guruh`],
      ['Topshirish ulushi', pct(e.submit_rate)],
      ['Qayta topshirish', pct(e.resubmit_rate)],
      ['Zaxira (qayta urinishlar)', pct(e.overhead)],
      ['Server', `$${e.server_usd_month} / oy`],
      ['To‘lov komissiyasi', pct(e.payment_fee)],
    ];
    $('#assumpList').innerHTML = items.map(([k, v]) => `<div><dt>${k}</dt><dd>${esc(v)}</dd></div>`).join('');
    $('#assumpNote').textContent = e.notes || '';
  }

  // ---------------------------------------------------------------- Ishga tushirish
  const cached = store.get(SECRET_KEY);
  if (cached?.economics) openSecret(cached);
  renderPricing(FALLBACK);
  renderDownloads(FALLBACK.downloads);

  api('/site/public').then((info) => {
    if (info.plans?.length) renderPricing(info);
    if (info.downloads) renderDownloads(info.downloads);
    if (!info.secret_enabled) $('#secretHint').textContent = 'Parol hali o‘rnatilmagan: Admin panel → Sayt bo‘limida o‘rnating';
    const checked = info.stats?.checked || 0;
    if (checked >= 100) {
      $('#metricLive').innerHTML = `<dt><span data-count="${checked}">0</span> ta</dt><dd>ishni AI allaqachon tekshirgan</dd>`;
      countIO.observe($('#metricLive [data-count]'));
    }
  }).catch(() => { /* zaxira qiymatlar ko'rsatilgan */ });
})();
