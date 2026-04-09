const state = {
  locks: [],
  status: null,
  blockcheckMeta: null,
  lastRecommendation: null,
  blockcheckJobId: null,
};

const views = {
  status: document.getElementById('view-status'),
  strategies: document.getElementById('view-strategies'),
  blockcheck: document.getElementById('view-blockcheck'),
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
    await new Promise((resolve) => window.setTimeout(resolve, 1500));
  }
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

async function refreshAll() {
  const [status, locks, blockcheckMeta, lastRecommendation] = await Promise.all([
    api('/cgi-bin/status.cgi'),
    api('/cgi-bin/locks.cgi'),
    api('/cgi-bin/blockcheck-meta.cgi'),
    api('/cgi-bin/blockcheck-last.cgi'),
  ]);
  state.status = status;
  state.locks = locks.profiles;
  state.blockcheckMeta = blockcheckMeta;
  renderStatus();
  renderStrategies();
  populateBlockcheckForms();
  renderBlockcheckRecommendation(lastRecommendation);
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

refreshAll().catch((error) => {
  showBanner(error.message, 'error');
});
