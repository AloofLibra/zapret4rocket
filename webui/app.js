const state = {
  meta: {},
  locks: [],
  status: null,
};

const views = {
  status: document.getElementById('view-status'),
  strategies: document.getElementById('view-strategies'),
};

const busyLabels = new WeakMap();

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

function setBusy(element, busy, label) {
  if (!element) return;
  if (busy) {
    if (!busyLabels.has(element)) {
      busyLabels.set(element, element.textContent);
    }
    element.disabled = true;
    element.setAttribute('aria-busy', 'true');
    if (label) {
      element.textContent = label;
    }
    return;
  }
  element.disabled = false;
  element.removeAttribute('aria-busy');
  if (busyLabels.has(element)) {
    element.textContent = busyLabels.get(element);
    busyLabels.delete(element);
  }
}

async function withBusy(element, label, task) {
  setBusy(element, true, label);
  try {
    return await task();
  } finally {
    setBusy(element, false);
  }
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

function applyTheme(theme) {
  const normalized = ['auto', 'light', 'dark'].includes(theme) ? theme : 'auto';
  document.documentElement.dataset.theme = normalized;
  document.body.dataset.theme = normalized;
  const select = document.getElementById('theme-mode');
  if (select) {
    select.value = normalized;
  }
}

function initTheme() {
  let savedTheme = 'auto';
  try {
    savedTheme = localStorage.getItem('z2r-theme') || 'auto';
  } catch (_) {
    savedTheme = 'auto';
  }
  const select = document.getElementById('theme-mode');
  applyTheme(savedTheme);
  if (select) {
    select.addEventListener('change', () => {
      try {
        localStorage.setItem('z2r-theme', select.value);
      } catch (_) {
        // Theme still applies for the current session when storage is unavailable.
      }
      applyTheme(select.value);
    });
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
    ['Локи стратегий', state.status.strategy_locks_status],
    ['Фильтр', state.status.hostlist_mode],
    ['FW', state.status.fwtype],
    ['Offload', state.status.flowoffload],
    ['TLS blob', state.status.tls_blob_mode],
  ];

  cards.forEach(([label, value]) => {
    const node = statTemplate.content.firstElementChild.cloneNode(true);
    node.querySelector('.label').textContent = label;
    node.querySelector('.value').textContent = value ?? '—';
    statusCards.appendChild(node);
  });

  const profiles = Array.isArray(state.status.profiles) ? state.status.profiles : [];
  profiles.forEach((profile) => {
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
    const form = node.querySelector('.lock-form');
    const submitButton = form.querySelector('button[type="submit"]');
    const clearButton = node.querySelector('.clear-lock');

    input.min = '1';
    input.max = String(profile.max_strategy);
    if (profile.current_lock && profile.current_lock !== '0') {
      input.value = profile.current_lock;
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const value = Number(input.value);
      if (!value) {
        showBanner('Введите номер стратегии.', 'error');
        return;
      }
      try {
        await withBusy(submitButton, 'Сохранение...', async () => {
          await api('/cgi-bin/set-lock.cgi', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ profile: profile.profile, strategy: value }),
          });
          await refreshAll();
        });
        showBanner(`Стратегия ${value} сохранена для ${profile.label}.`);
      } catch (error) {
        showBanner(error.message, 'error');
      }
    });

    clearButton.addEventListener('click', async () => {
      try {
        await withBusy(clearButton, 'Сброс...', async () => {
          await api('/cgi-bin/clear-lock.cgi', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ profile: profile.profile }),
          });
          await refreshAll();
        });
        showBanner(`Lock снят для ${profile.label}.`);
      } catch (error) {
        showBanner(error.message, 'error');
      }
    });

    container.appendChild(node);
  });
}

function appendText(parent, tag, text, className) {
  const element = document.createElement(tag);
  if (className) {
    element.className = className;
  }
  element.textContent = text;
  parent.appendChild(element);
  return element;
}

function renderChecks(payload) {
  const container = document.getElementById('check-results');
  container.innerHTML = '';

  const results = Array.isArray(payload?.results) ? payload.results : [];
  if (!results.length) {
    container.classList.add('empty');
    container.textContent = 'Нет результатов проверки.';
    return;
  }

  container.classList.remove('empty');

  results.forEach((item) => {
    const article = document.createElement('article');
    article.className = 'check-item';

    const title = document.createElement('div');
    title.className = 'check-title';
    appendText(title, 'strong', item.label || 'Цель');
    appendText(title, 'span', item.target || '');

    const pair = document.createElement('div');
    pair.className = 'check-pair';
    appendText(pair, 'span', `TLS 1.2: ${item.tls12 ? 'OK' : 'FAIL'}`, item.tls12 ? 'ok' : 'bad');
    appendText(pair, 'span', `TLS 1.3: ${item.tls13 ? 'OK' : 'FAIL'}`, item.tls13 ? 'ok' : 'bad');

    article.append(title, pair);
    container.appendChild(article);
  });
}

async function refreshAll() {
  const [meta, status, locks] = await Promise.all([
    api('/cgi-bin/meta.cgi'),
    api('/cgi-bin/status.cgi'),
    api('/cgi-bin/locks.cgi'),
  ]);
  state.meta = meta;
  state.status = status;
  state.locks = locks.profiles || [];
  renderStatus();
  renderStrategies();
}

initTheme();

document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => switchView(tab.dataset.view));
});

document.getElementById('open-strategies').addEventListener('click', () => switchView('strategies'));
document.getElementById('refresh-status').addEventListener('click', (event) => {
  withBusy(event.currentTarget, 'Обновление...', refreshAll).catch((e) => showBanner(e.message, 'error'));
});
document.getElementById('refresh-locks').addEventListener('click', (event) => {
  withBusy(event.currentTarget, 'Обновление...', refreshAll).catch((e) => showBanner(e.message, 'error'));
});

document.getElementById('restart-service').addEventListener('click', async (event) => {
  try {
    await withBusy(event.currentTarget, 'Перезапуск...', async () => {
      await api('/cgi-bin/restart.cgi', { method: 'POST' });
      await refreshAll();
    });
    showBanner('zapret2 перезапущен.');
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

document.getElementById('run-check').addEventListener('click', async (event) => {
  try {
    const payload = await withBusy(event.currentTarget, 'Проверка...', () => api('/cgi-bin/check.cgi', { method: 'POST' }));
    renderChecks(payload);
    showBanner('Проверка завершена.');
  } catch (error) {
    showBanner(error.message, 'error');
  }
});

refreshAll().catch((error) => {
  showBanner(error.message, 'error');
});
