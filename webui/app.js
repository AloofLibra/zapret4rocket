const state = {
  meta: {},
  locks: [],
  status: null,
  builderMeta: { profiles: [] },
  builderCandidates: {},
  builderDiscoveryState: {},
  builderDiscoveryPayload: {},
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

function builderDiscoveryPayload(profileId) {
  return state.builderDiscoveryPayload[profileId] || { results: { top_results: [] } };
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function resultTone(result) {
  switch (result) {
    case 'valid':
      return 'ok';
    case 'unstable':
      return 'warn';
    default:
      return 'bad';
  }
}

function boolTone(value) {
  return value ? 'ok' : 'bad';
}

function metricChip(label, value, tone = '') {
  if (value === undefined || value === null || value === '') return '';
  return `<span class="metric-chip ${tone}"><strong>${escapeHtml(label)}</strong>${escapeHtml(value)}</span>`;
}

function renderDiscoveryResult(item) {
  const tone = resultTone(item.result);
  const tls12Ok = Number(item.tls12_ok || 0) > 0;
  const tls13Ok = Number(item.tls13_ok || 0) > 0;
  const longGetOk = Number(item.long_get_ok || 0) > 0;
  const transportOk = item.transport_ok === true || item.transport_ok === 'true';
  const confidence = item.confidence ?? '';
  const family = item.family || '';
  const summaryChips = [
    metricChip('result', `${item.result} / ${item.score}`, tone),
    metricChip('elapsed', `${item.elapsed_ms} ms`),
    metricChip('confidence', confidence, confidence >= 80 ? 'ok' : confidence >= 50 ? 'warn' : 'bad'),
    metricChip('family', family),
  ].filter(Boolean).join('');
  const qualityChips = [
    metricChip('failure', item.failure_class || 'n/a', item.failure_class === 'success' ? 'ok' : item.failure_class && item.failure_class !== 'inconclusive' ? 'warn' : ''),
    metricChip('dns', item.dns_state || 'unknown', item.dns_state === 'ok' ? 'ok' : item.dns_state === 'fail' ? 'bad' : 'warn'),
    metricChip('baseline', item.baseline_state || 'unknown', item.baseline_state === 'ok' ? 'ok' : item.baseline_state === 'fail' ? 'bad' : 'warn'),
    metricChip('tls12', tls12Ok ? 'ok' : 'fail', boolTone(tls12Ok)),
    metricChip('tls13', tls13Ok ? 'ok' : 'fail', boolTone(tls13Ok)),
    metricChip('long_get', longGetOk ? 'ok' : 'fail', boolTone(longGetOk)),
    metricChip('transport', transportOk ? 'ok' : 'fail', boolTone(transportOk)),
  ].filter(Boolean).join('');

  return `
    <article class="check-item discovery-item">
      <div class="check-title">
        <strong>${escapeHtml(item.candidate)}</strong>
        <span>${escapeHtml(item.label || '')}</span>
      </div>
      <div class="metric-row">${summaryChips}</div>
      <div class="metric-row metric-row-secondary">${qualityChips}</div>
    </article>
  `;
}

function renderRecommendation(item) {
  if (!item || !item.candidate) return '';
  const tone = resultTone(item.result);
  return `
    <div class="builder-recommendation">
      <div class="builder-recommendation-title">
        <span>Recommended</span>
        <strong>${escapeHtml(item.candidate)}</strong>
      </div>
      <div class="metric-row">
        ${metricChip('label', item.label || '')}
        ${metricChip('result', `${item.result} / ${item.score}`, tone)}
        ${metricChip('confidence', item.confidence ?? '', (item.confidence ?? 0) >= 80 ? 'ok' : (item.confidence ?? 0) >= 50 ? 'warn' : 'bad')}
        ${metricChip('failure', item.failure_class || 'n/a', item.failure_class === 'success' ? 'ok' : 'warn')}
      </div>
    </div>
  `;
}

function ensureDiscoveryPolling() {
  const running = Object.values(state.builderDiscoveryState).some((item) => item && item.running);
  if (running && !ensureDiscoveryPolling.timer) {
    ensureDiscoveryPolling.timer = window.setInterval(() => {
      if (ensureDiscoveryPolling.pending) return;
      ensureDiscoveryPolling.pending = true;
      refreshAll().catch(() => {}).finally(() => {
        ensureDiscoveryPolling.pending = false;
      });
    }, 6000);
  }
  if (!running && ensureDiscoveryPolling.timer) {
    window.clearInterval(ensureDiscoveryPolling.timer);
    ensureDiscoveryPolling.timer = null;
    ensureDiscoveryPolling.pending = false;
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
  const recommendation = payload.last_session && payload.last_session.recommended_candidate
    ? payload.last_session.recommended_candidate
    : null;
  const results = (payload.last_session && payload.last_session.results) || [];
  const discoveryPayload = builderDiscoveryPayload(profile.profile);
  const liveProgress = discoveryPayload && discoveryPayload.results && discoveryPayload.results.top_results
    ? discoveryPayload.results
    : {};
  const liveResults = Array.isArray(liveProgress.top_results) ? liveProgress.top_results : [];
  const showingResults = discovery.running ? liveResults : results;

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
      ${discovery.running ? `
      <div class="meta-line">
        <span>Progress</span>
        <strong>${liveProgress.phase || 'starting'}${liveProgress.tier ? ` / ${liveProgress.tier}` : ''} · ${liveProgress.checked || 0}/${liveProgress.total || 0}</strong>
      </div>
      <div class="progress-track"><span class="progress-fill" style="width:${liveProgress.total ? Math.max(6, Math.min(100, Math.round(((liveProgress.checked || 0) / liveProgress.total) * 100))) : 8}%"></span></div>
      ` : ''}
    </div>
    ${renderRecommendation(recommendation)}
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

  if (discovery.running) {
    const stopButton = document.createElement('button');
    stopButton.type = 'button';
    stopButton.className = 'ghost danger-button';
    stopButton.textContent = 'Stop discovery';
    stopButton.addEventListener('click', async () => {
      try {
        await api('/cgi-bin/discovery-stop.cgi', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ profile: profile.profile }),
        });
        showBanner(`Discovery stopped for ${profile.label}.`, 'error');
        await refreshAll();
      } catch (error) {
        showBanner(error.message, 'error');
      }
    });
    actions.appendChild(stopButton);
  }

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

  if (showingResults.length > 0) {
    const list = document.createElement('div');
    list.className = 'checks';
    list.innerHTML = showingResults.slice(0, 5).map(renderDiscoveryResult).join('');
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
  const discoveryRunning = Object.values(state.builderDiscoveryState).some((item) => item && item.running);
  const [meta, status, locks, builderMeta, builder1, builder2, discovery1, discovery2] = await Promise.all([
    api('/cgi-bin/meta.cgi'),
    api('/cgi-bin/status.cgi'),
    api('/cgi-bin/locks.cgi'),
    safeApi('/cgi-bin/builder-meta.cgi', {}, { profiles: [] }),
    discoveryRunning ? Promise.resolve(state.builderCandidates[1] || { profile: 1, candidates: [], last_session: { results: [] } }) : safeApi('/cgi-bin/builder-candidates.cgi?profile=1', {}, { profile: 1, candidates: [], last_session: { results: [] } }),
    discoveryRunning ? Promise.resolve(state.builderCandidates[2] || { profile: 2, candidates: [], last_session: { results: [] } }) : safeApi('/cgi-bin/builder-candidates.cgi?profile=2', {}, { profile: 2, candidates: [], last_session: { results: [] } }),
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
  state.builderDiscoveryPayload = {
    1: discovery1 || { results: { top_results: [] } },
    2: discovery2 || { results: { top_results: [] } },
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
