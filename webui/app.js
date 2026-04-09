const state = {
  meta: {},
  locks: [],
  status: null,
};

const views = {
  status: document.getElementById('view-status'),
  strategies: document.getElementById('view-strategies'),
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

async function refreshAll() {
  const [meta, status, locks] = await Promise.all([
    api('/cgi-bin/meta.cgi'),
    api('/cgi-bin/status.cgi'),
    api('/cgi-bin/locks.cgi'),
  ]);
  state.meta = meta;
  state.status = status;
  state.locks = locks.profiles;
  renderStatus();
  renderStrategies();
}

document.querySelectorAll('.tab').forEach((tab) => {
  tab.addEventListener('click', () => switchView(tab.dataset.view));
});

document.getElementById('open-strategies').addEventListener('click', () => switchView('strategies'));
document.getElementById('refresh-status').addEventListener('click', () => refreshAll().catch((e) => showBanner(e.message, 'error')));
document.getElementById('refresh-locks').addEventListener('click', () => refreshAll().catch((e) => showBanner(e.message, 'error')));

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

refreshAll().catch((error) => {
  showBanner(error.message, 'error');
});
