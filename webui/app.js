const state = {
  locks: [],
  status: null,
  blockcheckMeta: null,
  lastRecommendation: null,
  blockcheckJobId: null,
  analyticsMeta: null,
  analyticsJobId: null,
  lastAnalytics: null,
};

const views = {
  status: document.getElementById('view-status'),
  strategies: document.getElementById('view-strategies'),
  blockcheck: document.getElementById('view-blockcheck'),
  analytics: document.getElementById('view-analytics'),
};

function showBanner(message, type = 'success') {
  const banner = document.getElementById('banner');
  banner.textContent = message;
  banner.className = `banner ${type}`;
  banner.hidden = false;
  window.clearTimeout(showBanner._timer);
  showBanner._timer = window.setTimeout(() => {
    banner.hidden = true;
  }, 3500);
}

async function api(path, options = {}) {
  const response = await fetch(path, options);
  let data = {};
  try {
    data = await response.json();
  } catch (_) {
    data = {};
  }
  if (!response.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

async function waitForBlockcheckJob(jobId) {
  state.blockcheckJobId = jobId;
  for (;;) {
    const payload = await api(`/cgi-bin/blockcheck-job.cgi?job=${encodeURIComponent(jobId)}`);
    if (payload.status === 'completed') {
      state.blockcheckJobId = null;
      return payload;
    }
    if (payload.status === 'error') {
      state.blockcheckJobId = null;
      throw new Error(payload.error || 'Blockcheck job failed');
    }
    renderBlockcheckProgress(payload);
    await new Promise((resolve) => window.setTimeout(resolve, 1500));
  }
}

async function waitForAnalyticsJob(jobId) {
  state.analyticsJobId = jobId;
  for (;;) {
    const payload = await api(`/cgi-bin/analytics-job.cgi?job=${encodeURIComponent(jobId)}`);
    if (payload.status === 'completed') {
      state.analyticsJobId = null;
      return payload;
    }
    if (payload.status === 'error') {
      state.analyticsJobId = null;
      throw new Error(payload.error || 'Analytics job failed');
    }
    renderAnalyticsProgress(payload);
    await new Promise((resolve) => window.setTimeout(resolve, 1500));
  }
}

function renderBlockcheckProgress(payload) {
  const container = document.getElementById('blockcheck-results');
  const current = payload.current || 0;
  const total = payload.total || 0;
  const strategy = payload.strategy ?? '-';
  container.classList.remove('empty');
  container.innerHTML = `
    <article class="check-item recommendation">
      <strong>Проверка выполняется</strong>
      <span>Профиль: ${payload.profile_name || payload.profile_id || '-'}</span>
      <span>Цель: ${payload.target || '-'}</span>
      <span>Этап: ${payload.phase || 'running'}</span>
      <span>Прогресс: ${current}/${total}</span>
      <span>Стратегия: ${strategy}</span>
      <span>Последний результат: ${payload.last_result || '-'}</span>
      <span>${payload.last_reason || ''}</span>
    </article>
  `;
}

function renderAnalyticsProgress(payload) {
  const container = document.getElementById('analytics-summary');
  container.classList.remove('empty');
  container.innerHTML = `
    <article class="check-item recommendation">
      <strong>Аналитический отчёт формируется</strong>
      <span>Профиль: ${payload.profile_name || payload.profile_id || '-'}</span>
      <span>Цель: ${payload.target || '-'}</span>
      <span>Этап: ${payload.phase || 'running'}</span>
      <span>${payload.status_text || ''}</span>
    </article>
  `;
}

function switchView(view) {
  Object.entries(views).forEach(([name, element]) => {
    element.classList.toggle('is-active', name === view);
  });
  document.querySelectorAll('.tab').forEach((tab) => {
    tab.classList.toggle('is-active', tab.dataset.view === view);
  });
}

function renderStatus() {
  if (!state.status) return;

  const statusCards = document.getElementById('status-cards');
  const statusProfiles = document.getElementById('status-profiles');
  const statTemplate = document.getElementById('status-card-template');
  const profileTemplate = document.getElementById('status-profile-template');

  statusCards.innerHTML = '';
  statusProfiles.innerHTML = '';

  const cards = [
    ['zapret2', state.status.zapret2_running ? 'Запущен' : 'Остановлен'],
    ['Оркестратор', state.status.orchestra_status],
    ['Фильтр', state.status.hostlist_mode],
    ['FW', state.status.fwtype],
    ['Offload', state.status.flowoffload],
    ['TLS blob', state.status.tls_blob_mode],
  ];

  cards.forEach(([label, value]) => {
    const node = statTemplate.content.firstElementChild.cloneNode(true);
    node.querySelector('.label').textContent = label;
    node.querySelector('.value').textContent = value;
    statusCards.appendChild(node);
  });

  state.status.profiles.forEach((profile) => {
    const node = profileTemplate.content.firstElementChild.cloneNode(true);
    node.querySelector('h3').textContent = profile.label;
    node.querySelector('.desc').textContent = profile.description;
    node.querySelector('.current-lock').textContent = profile.current_lock || '0';
    statusProfiles.appendChild(node);
  });
}

function renderStrategies() {
  const container = document.getElementById('strategy-cards');
  const template = document.getElementById('strategy-card-template');
  container.innerHTML = '';

  state.locks.forEach((profile) => {
    const node = template.content.firstElementChild.cloneNode(true);
    node.querySelector('h3').textContent = profile.label;
    node.querySelector('.desc').textContent = profile.description;
    node.querySelector('.chip').textContent = `Профиль ${profile.profile}`;
    node.querySelector('.current-lock').textContent = profile.current_lock || '0';
    node.querySelector('.max-lock').textContent = String(profile.max_strategy);

    const input = node.querySelector('input');
    input.min = '1';
    input.max = String(profile.max_strategy);
    if (profile.current_lock && profile.current_lock !== '0') {
      input.value = profile.current_lock;
    }

    node.querySelector('.lock-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const value = Number(input.value);
      if (!value) {
        showBanner('Введите номер стратегии.', 'error');
        return;
      }
      try {
        await api('/cgi-bin/set-lock.cgi', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ profile: profile.profile, strategy: value }),
        });
        showBanner(`Стратегия ${value} сохранена для ${profile.label}.`);
        await refreshAll();
      } catch (error) {
        showBanner(error.message, 'error');
      }
    });

    node.querySelector('.clear-lock').addEventListener('click', async () => {
      try {
        await api('/cgi-bin/clear-lock.cgi', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ profile: profile.profile }),
        });
        showBanner(`Lock снят для ${profile.label}.`);
        await refreshAll();
      } catch (error) {
        showBanner(error.message, 'error');
      }
    });

    container.appendChild(node);
  });
}

function renderChecks(payload) {
  const container = document.getElementById('check-results');
  container.classList.remove('empty');
  container.innerHTML = '';

  payload.results.forEach((item) => {
    const article = document.createElement('article');
    article.className = 'check-item';
    article.innerHTML = `
      <div class="check-title">
        <strong>${item.label}</strong>
        <span>${item.target}</span>
      </div>
      <div class="check-pair">
        <span class="${item.tls12 ? 'ok' : 'bad'}">TLS 1.2: ${item.tls12 ? 'OK' : 'FAIL'}</span>
        <span class="${item.tls13 ? 'ok' : 'bad'}">TLS 1.3: ${item.tls13 ? 'OK' : 'FAIL'}</span>
      </div>
    `;
    container.appendChild(article);
  });
}

function populateBlockcheckForms() {
  if (!state.blockcheckMeta) return;
  const profileSelect = document.getElementById('blockcheck-profile-select');
  const customSelect = document.getElementById('blockcheck-custom-profile');
  profileSelect.innerHTML = '';
  customSelect.innerHTML = '<option value="auto">auto (Blocked Sites)</option>';

  state.blockcheckMeta.profiles.forEach((profile) => {
    const option = document.createElement('option');
    option.value = String(profile.profile);
    option.textContent = `${profile.profile}. ${profile.label}`;
    profileSelect.appendChild(option);

    const customOption = option.cloneNode(true);
    customSelect.appendChild(customOption);
  });
}

function populateAnalyticsForms() {
  if (!state.analyticsMeta) return;
  const select = document.getElementById('analytics-profile-select');
  select.innerHTML = '';
  state.analyticsMeta.profiles.forEach((profile) => {
    const option = document.createElement('option');
    option.value = String(profile.profile);
    option.textContent = `${profile.profile}. ${profile.label}`;
    select.appendChild(option);
  });
}

function renderBlockcheckRecommendation(recommendation) {
  const container = document.getElementById('blockcheck-recommendation');
  state.lastRecommendation = recommendation;

  if (!recommendation || !recommendation.profile_id) {
    container.classList.add('empty');
    container.textContent = 'Рекомендаций пока нет.';
    return;
  }

  container.classList.remove('empty');
  container.innerHTML = '';

  const article = document.createElement('article');
  article.className = 'check-item recommendation';
  article.innerHTML = `
    <strong>${recommendation.profile_name || 'Unknown'}</strong>
    <span>Цель: ${recommendation.target || '-'}</span>
    <span>Лучшая стратегия: ${recommendation.best_strategy ?? 'нет'}</span>
    <span>Запасные: ${(recommendation.backup_strategies || []).join(', ') || 'нет'}</span>
    <span>Неудачные: ${(recommendation.failed_strategies || []).join(', ') || 'нет'}</span>
    <span>${recommendation.reason_summary || ''}</span>
  `;
  container.appendChild(article);
}

function renderBlockcheckResults(results) {
  const container = document.getElementById('blockcheck-results');
  if (!results || !results.length) {
    container.classList.add('empty');
    container.textContent = 'Данные последней проверки отсутствуют.';
    return;
  }

  container.classList.remove('empty');
  container.innerHTML = '';
  results.forEach((item) => {
    const article = document.createElement('article');
    article.className = 'check-item';
    article.innerHTML = `
      <div class="check-title">
        <strong>Стратегия ${item.strategy}</strong>
        <span>${item.profile_name}</span>
      </div>
      <div class="check-pair">
        <span class="${item.result === 'ok' ? 'ok' : item.result === 'unstable' ? 'ok' : 'bad'}">${item.result}</span>
        <span>${item.reason}</span>
        <span>${item.elapsed_ms} ms</span>
      </div>
      <div class="check-pair">
        <span>${item.target}</span>
      </div>
    `;
    container.appendChild(article);
  });
}

function renderAnalyticsReport(report) {
  state.lastAnalytics = report;
  const summary = document.getElementById('analytics-summary');
  const dns = document.getElementById('analytics-dns');
  const transport = document.getElementById('analytics-transport');
  const blockcheck = document.getElementById('analytics-blockcheck');
  const hints = document.getElementById('analytics-hints');

  if (!report || !report.run_id) {
    summary.className = 'checks empty';
    dns.className = 'checks empty';
    transport.className = 'checks empty';
    blockcheck.className = 'checks empty';
    hints.className = 'checks empty';
    summary.textContent = 'Отчёт ещё не сформирован.';
    dns.textContent = 'DNS-диагностика будет показана здесь.';
    transport.textContent = 'Transport/TLS-диагностика будет показана здесь.';
    blockcheck.textContent = 'Связь со стратегиями будет показана здесь.';
    hints.textContent = 'Подсказки по стратегии будут показаны здесь.';
    return;
  }

  const summaryLabelMap = {
    dns_suspect: 'DNS issue',
    dns_mismatch: 'DNS issue',
    no_dns_answer: 'DNS issue',
    transport_blocked: 'Transport issue',
    tls_partial: 'Transport issue',
    likely_block_page: 'Block page',
    likely_redirect_or_stub: 'Block page',
    strategy_sensitive: 'Strategy-sensitive',
    unclear: 'Unclear',
  };

  summary.className = 'checks';
  summary.innerHTML = `
    <article class="check-item recommendation">
      <div class="check-title">
        <strong>${report.target}</strong>
        <span class="chip">${summaryLabelMap[report.summary?.blocking_class] || 'Unclear'}</span>
      </div>
      <span>Профиль: ${report.profile_name || report.profile_id || '-'}</span>
      <span>Время: ${report.created_at || '-'}</span>
      <span>${report.summary?.short_text || ''}</span>
      <span>${report.summary?.recommendation_note || ''}</span>
    </article>
  `;

  const comparisonCards = (report.dns?.comparisons || []).map((item) => `
    <article class="check-item">
      <div class="check-title">
        <strong>${item.name}</strong>
        <span>${item.method}</span>
      </div>
      <div class="check-pair">
        <span>${(item.ips || []).join(', ') || 'нет ответа'}</span>
      </div>
      <div class="check-pair">
        <span>${item.status_text || ''}</span>
      </div>
    </article>
  `).join('');

  dns.className = 'checks';
  dns.innerHTML = `
    <article class="check-item recommendation">
      <strong>DNS</strong>
      <span>Hostname: ${report.dns?.hostname || '-'}</span>
      <span>${report.dns?.summary || ''}</span>
      <span>System DNS: ${(report.dns?.system?.ips || []).join(', ') || 'нет ответа'}</span>
      <span>Флаги: ${(report.dns?.suspicious_flags || []).join(', ') || 'нет'}</span>
    </article>
    ${comparisonCards || '<article class="check-item">Нет данных сравнения.</article>'}
  `;

  const transportRows = ['plain', 'tls12', 'tls13'].map((key) => {
    const item = report.transport?.[key] || {};
    return `
      <article class="check-item">
        <div class="check-title">
          <strong>${key.toUpperCase()}</strong>
          <span class="${item.verdict === 'ok' ? 'ok' : 'bad'}">${item.verdict || 'unknown'}</span>
        </div>
        <div class="check-pair">
          <span>HTTP: ${item.http_code || '-'}</span>
          <span>${item.error_class || 'no error class'}</span>
        </div>
        <div class="check-pair">
          <span>${item.redirect_url || ''}</span>
        </div>
        <div class="check-pair">
          <span>${item.snippet || ''}</span>
        </div>
      </article>
    `;
  }).join('');

  transport.className = 'checks';
  transport.innerHTML = `
    <article class="check-item recommendation">
      <strong>Transport / TLS</strong>
      <span>${report.transport?.summary || ''}</span>
    </article>
    ${transportRows}
  `;

  const resultCards = (report.blockcheck?.results || []).map((item) => `
    <article class="check-item">
      <div class="check-title">
        <strong>Стратегия ${item.strategy}</strong>
        <span class="${item.result === 'ok' ? 'ok' : item.result === 'unstable' ? 'ok' : 'bad'}">${item.result}</span>
      </div>
      <div class="check-pair">
        <span>${item.reason || ''}</span>
        <span>${item.elapsed_ms || 0} ms</span>
      </div>
    </article>
  `).join('');

  blockcheck.className = 'checks';
  blockcheck.innerHTML = `
    <article class="check-item recommendation">
      <strong>Blockcheck / стратегии</strong>
      <span>Лучшая: ${report.blockcheck?.best_strategy ?? 'нет'}</span>
      <span>Запасные: ${(report.blockcheck?.backup_strategies || []).join(', ') || 'нет'}</span>
      <span>Неудачные: ${(report.blockcheck?.failed_strategies || []).join(', ') || 'нет'}</span>
      <span>Стабильных: ${report.blockcheck?.stable_count || 0}, нестабильных: ${report.blockcheck?.unstable_count || 0}, fail: ${report.blockcheck?.fail_count || 0}</span>
    </article>
    ${resultCards || '<article class="check-item">Детали blockcheck отсутствуют.</article>'}
  `;

  hints.className = 'checks';
  hints.innerHTML = (report.hints || []).length
    ? (report.hints || []).map((hint) => `<article class="check-item"><strong>Подсказка</strong><span>${hint}</span></article>`).join('')
    : '<article class="check-item">Подсказок пока нет.</article>';
}

async function refreshAll() {
  const [status, locks, blockcheckMeta, lastRecommendation, analyticsMeta, analyticsLast] = await Promise.all([
    api('/cgi-bin/status.cgi'),
    api('/cgi-bin/locks.cgi'),
    api('/cgi-bin/blockcheck-meta.cgi'),
    api('/cgi-bin/blockcheck-last.cgi'),
    api('/cgi-bin/analytics-meta.cgi'),
    api('/cgi-bin/analytics-last.cgi'),
  ]);
  state.status = status;
  state.locks = locks.profiles;
  state.blockcheckMeta = blockcheckMeta;
  state.analyticsMeta = analyticsMeta;
  renderStatus();
  renderStrategies();
  populateBlockcheckForms();
  populateAnalyticsForms();
  renderBlockcheckRecommendation(lastRecommendation);
  renderAnalyticsReport(analyticsLast);
}

document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => switchView(tab.dataset.view));
});

document.getElementById('open-strategies').addEventListener('click', () => switchView('strategies'));
document.getElementById('refresh-status').addEventListener('click', () => refreshAll().catch((e) => showBanner(e.message, 'error')));
document.getElementById('refresh-locks').addEventListener('click', () => refreshAll().catch((e) => showBanner(e.message, 'error')));
document.getElementById('refresh-blockcheck').addEventListener('click', async () => {
  try {
    const payload = await api('/cgi-bin/blockcheck-last.cgi');
    renderBlockcheckRecommendation(payload);
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('restart-service').addEventListener('click', async () => {
  try {
    await api('/cgi-bin/restart.cgi', { method: 'POST' });
    showBanner('zapret2 перезапущен.');
    await refreshAll();
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('run-check').addEventListener('click', async () => {
  try {
    const payload = await api('/cgi-bin/check.cgi', { method: 'POST' });
    renderChecks(payload);
    showBanner('Проверка завершена.');
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('blockcheck-profile-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const profile = document.getElementById('blockcheck-profile-select').value;
  const resultsContainer = document.getElementById('blockcheck-results');
  resultsContainer.classList.remove('empty');
  resultsContainer.textContent = 'Проверка выполняется...';
  try {
    const started = await api('/cgi-bin/blockcheck-profile-start.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ profile }),
    });
    const payload = await waitForBlockcheckJob(started.job_id);
    renderBlockcheckResults(payload.results);
    renderBlockcheckRecommendation(payload.recommendation);
    showBanner('Проверка профиля завершена.');
    await refreshAll();
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('blockcheck-custom-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const target = document.getElementById('blockcheck-target').value.trim();
  const profile = document.getElementById('blockcheck-custom-profile').value;
  if (!target) {
    showBanner('Введите домен или URL.', 'error');
    return;
  }
  const resultsContainer = document.getElementById('blockcheck-results');
  resultsContainer.classList.remove('empty');
  resultsContainer.textContent = 'Проверка выполняется...';
  try {
    const started = await api('/cgi-bin/blockcheck-custom-start.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ target, profile }),
    });
    const payload = await waitForBlockcheckJob(started.job_id);
    renderBlockcheckResults(payload.results);
    renderBlockcheckRecommendation(payload.recommendation);
    showBanner('Кастомная проверка завершена.');
    await refreshAll();
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('apply-blockcheck').addEventListener('click', async () => {
  try {
    await api('/cgi-bin/blockcheck-apply.cgi', { method: 'POST' });
    showBanner('Рекомендация применена.');
    await refreshAll();
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('analytics-refresh').addEventListener('click', async () => {
  try {
    const payload = await api('/cgi-bin/analytics-last.cgi');
    renderAnalyticsReport(payload);
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('analytics-last-run').addEventListener('click', async () => {
  try {
    const started = await api('/cgi-bin/analytics-start.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ mode: 'last' }),
    });
    const payload = await waitForAnalyticsJob(started.job_id);
    renderAnalyticsReport(payload.report);
    showBanner('Аналитический отчёт по последнему blockcheck готов.');
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('analytics-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const target = document.getElementById('analytics-target').value.trim();
  const profile = document.getElementById('analytics-profile-select').value;
  if (!target) {
    showBanner('Введите домен или URL для анализа.', 'error');
    return;
  }
  try {
    const started = await api('/cgi-bin/analytics-start.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ mode: 'target', target, profile }),
    });
    const payload = await waitForAnalyticsJob(started.job_id);
    renderAnalyticsReport(payload.report);
    showBanner('Полный аналитический отчёт готов.');
    await refreshAll();
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

refreshAll().catch((error) => {
  showBanner(error.message, 'error');
});
