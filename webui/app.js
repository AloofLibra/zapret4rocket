const state = {
  meta: {},
  locks: [],
  status: null,
  builderMeta: { profiles: [] },
  builderCandidates: {},
  builderDiscoveryState: {},
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

async function safeApi(path, options = {}, fallback = null) {
  try {
    return await api(path, options);
  } catch (_) {
    return fallback;
  }
}

function switchView(view) {
  Object.entries(views).forEach(([name, element]) => {
    if (!element) return;
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

function builderProfileInfo(profileId) {
  const profiles = Array.isArray(state.builderMeta.profiles)
    ? state.builderMeta.profiles
    : (Array.isArray(state.builderMeta.catalog?.profiles) ? state.builderMeta.catalog.profiles : []);
  return profiles.find((item) => Number(item.profile) === Number(profileId));
}

function builderPayload(profileId) {
  return state.builderCandidates[profileId] || { candidates: [], last_session: { results: [] } };
}

function builderDiscoveryState(profileId) {
  return state.builderDiscoveryState[profileId] || { running: false, status: 'idle', message: 'No active discovery' };
}

function ensureDiscoveryPolling() {
  const running = Object.values(state.builderDiscoveryState).some((item) => item && item.running);
  if (running && !ensureDiscoveryPolling.timer) {
    ensureDiscoveryPolling.timer = window.setInterval(() => {
      refreshAll().catch(() => {});
    }, 3000);
  }
  if (!running && ensureDiscoveryPolling.timer) {
    window.clearInterval(ensureDiscoveryPolling.timer);
    ensureDiscoveryPolling.timer = null;
  }
}

function makeBuilderPanel(profile) {
  const info = builderProfileInfo(profile.profile);
  if (!info || !info.supported) return null;

  const payload = builderPayload(profile.profile);
  const discovery = builderDiscoveryState(profile.profile);
  const panel = document.createElement('section');
  panel.className = 'panel';
  const activeText = info.active_candidate
    ? `${info.active_candidate} / strategy ${info.active_strategy || '0'}`
    : 'none';

  panel.innerHTML = `
    <div class="panel-header">
      <h2>Builder</h2>
    </div>
    <div class="meta">
      <div class="meta-line">
        <span>Active generated</span>
        <strong>${activeText}</strong>
      </div>
      <div class="meta-line">
        <span>Discovery</span>
        <strong class="builder-status builder-status-${discovery.status || 'idle'}">${discovery.message || discovery.status || 'idle'}</strong>
      </div>
    </div>
  `;

  const actions = document.createElement('div');
  actions.className = 'card-actions';

  const discoverButton = document.createElement('button');
  discoverButton.type = 'button';
  discoverButton.className = 'primary';
  discoverButton.textContent = discovery.running ? 'Discovery running...' : 'Run discovery';
  discoverButton.disabled = Boolean(discovery.running);
  discoverButton.addEventListener('click', async () => {
    try {
      const payload = await api('/cgi-bin/discovery-start.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ profile: profile.profile }),
      });
      if (payload.queued) {
        showBanner(`Discovery поставлен в очередь для ${profile.label}.`);
      } else {
        showBanner(`Discovery завершён для ${profile.label}.`);
      }
      await refreshAll();
    } catch (error) {
      showBanner(error.message, 'error');
    }
  });
  actions.appendChild(discoverButton);

  if (payload.candidates.length > 0) {
    const select = document.createElement('select');
    payload.candidates.forEach((candidate) => {
      const option = document.createElement('option');
      option.value = candidate.candidate;
      option.textContent = `${candidate.candidate} - ${candidate.label}`;
      if (candidate.active) option.selected = true;
      select.appendChild(option);
    });
    actions.appendChild(select);

    const applyButton = document.createElement('button');
    applyButton.type = 'button';
    applyButton.className = 'ghost';
    applyButton.textContent = 'Apply candidate';
    applyButton.addEventListener('click', async () => {
      try {
        const payload = await api('/cgi-bin/apply-candidate.cgi', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ profile: profile.profile, candidate: select.value }),
        });
        if (payload.queued && !payload.applied) {
          showBanner(`Candidate ${select.value} поставлен в очередь для ${profile.label}.`);
        } else {
          showBanner(`Candidate ${select.value} применён для ${profile.label}.`);
        }
        await refreshAll();
      } catch (error) {
        showBanner(error.message, 'error');
      }
    });
    actions.appendChild(applyButton);
  }

  panel.appendChild(actions);

  const results = (payload.last_session && payload.last_session.results) || [];
  if (results.length > 0) {
    const list = document.createElement('div');
    list.className = 'checks';
    list.innerHTML = results.slice(0, 3).map((item) => `
      <article class="check-item">
        <div class="check-title">
          <strong>${item.candidate}</strong>
          <span>${item.label}</span>
        </div>
        <div class="check-pair">
          <span class="${item.result === 'fail' ? 'bad' : 'ok'}">${item.result} / score ${item.score}</span>
          <span>elapsed ${item.elapsed_ms} ms</span>
        </div>
      </article>
    `).join('');
    panel.appendChild(list);
  }

  return panel;
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

    const builderPanel = makeBuilderPanel(profile);
    if (builderPanel) {
      node.appendChild(builderPanel);
    }

    container.appendChild(node);
  });
}

async function refreshAll() {
  const [meta, status, locks, builderMeta, builder1, builder2, discovery1, discovery2] = await Promise.all([
    api('/cgi-bin/meta.cgi'),
    api('/cgi-bin/status.cgi'),
    api('/cgi-bin/locks.cgi'),
    safeApi('/cgi-bin/builder-meta.cgi', {}, { profiles: [] }),
    safeApi('/cgi-bin/builder-candidates.cgi?profile=1', {}, { profile: 1, candidates: [], last_session: { results: [] } }),
    safeApi('/cgi-bin/builder-candidates.cgi?profile=2', {}, { profile: 2, candidates: [], last_session: { results: [] } }),
    safeApi('/cgi-bin/discovery-results.cgi?profile=1', {}, { discovery_state: { running: false, status: 'idle', message: 'No active discovery' } }),
    safeApi('/cgi-bin/discovery-results.cgi?profile=2', {}, { discovery_state: { running: false, status: 'idle', message: 'No active discovery' } }),
  ]);

  state.meta = meta;
  state.status = status;
  state.locks = locks.profiles;
  state.builderMeta = builderMeta || { profiles: [] };
  state.builderCandidates = {
    1: builder1 || { candidates: [], last_session: { results: [] } },
    2: builder2 || { candidates: [], last_session: { results: [] } },
  };
  state.builderDiscoveryState = {
    1: (discovery1 && discovery1.discovery_state) || { running: false, status: 'idle', message: 'No active discovery' },
    2: (discovery2 && discovery2.discovery_state) || { running: false, status: 'idle', message: 'No active discovery' },
  };
  renderStatus();
  renderStrategies();
  ensureDiscoveryPolling();
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
