const API = '';
(function applySimQueryParams() {
  const params = new URLSearchParams(location.search);
  if (params.get('fresh') === '1') {
    localStorage.removeItem('madamis_token');
    localStorage.removeItem('madamis_playerId');
  }
  const simDevice = params.get('deviceId');
  if (simDevice) {
    localStorage.setItem('madamis_deviceId', simDevice);
  }
})();

let token = localStorage.getItem('madamis_token') || '';
let playerId = localStorage.getItem('madamis_playerId') || '';
let ws = null;
let wsPingInterval = null;
let wsReconnectTimer = null;
let refreshPromise = null;
let state = {};
let timerInterval = null;

function getDeviceId() {
  let id = localStorage.getItem('madamis_deviceId');
  if (!id) {
    id = (typeof crypto !== 'undefined' && crypto.randomUUID)
      ? crypto.randomUUID()
      : `dev-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    localStorage.setItem('madamis_deviceId', id);
  }
  return id;
}

const phaseScreens = {
  lobby: 'waiting',
  synopsis: 'synopsis',
  private_reading: 'script',
  investigation: 'investigation',
  discussion: 'discussion',
  accusation: 'accusation',
  voting: 'voting',
  truth_reveal: 'truth',
  epilogue: 'truth',
  results: 'results',
};

const phaseLabels = {
  lobby: '待機',
  synopsis: 'あらすじ',
  private_reading: '個人台本',
  investigation: '調査',
  discussion: '議論',
  accusation: '推理発表',
  voting: '投票',
  truth_reveal: '真相',
  epilogue: '後日談',
  results: '結果',
  join: '参加',
  character: '配役選択',
  waiting: '待機',
};

const importanceLabels = {
  critical: '最重要',
  important: '重要',
  supplementary: '補足',
};

function updateStatusBar(phase, timeoutAt) {
  const phaseEl = document.getElementById('status-phase');
  const timerEl = document.getElementById('status-timer');
  if (phaseEl) phaseEl.textContent = phaseLabels[phase] || phase;

  if (timeoutAt && timerEl) {
    startPhaseTimer(timeoutAt, 'status-timer');
  } else if (timerEl) {
    timerEl.classList.add('hidden');
  }
}

function showScreen(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  const el = document.getElementById(`screen-${id}`);
  if (el) el.classList.add('active');
}

function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  setTimeout(() => t.classList.add('hidden'), 3000);
}

function showPhaseBanner(label) {
  const b = document.getElementById('phase-banner');
  b.textContent = label;
  b.classList.remove('hidden');
  setTimeout(() => b.classList.add('hidden'), 3000);
}

async function api(method, path, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(`${API}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
}

function disconnectWs() {
  if (wsPingInterval) {
    clearInterval(wsPingInterval);
    wsPingInterval = null;
  }
  if (wsReconnectTimer) {
    clearTimeout(wsReconnectTimer);
    wsReconnectTimer = null;
  }
  if (ws) {
    ws.onclose = null;
    ws.close();
    ws = null;
  }
}

function connectWs() {
  if (!token) return;
  disconnectWs();
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onopen = () => {
    ws.send(JSON.stringify({ type: 'auth', token }));
    wsPingInterval = setInterval(() => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'ping' }));
      }
    }, 30000);
  };
  ws.onmessage = (e) => {
    const data = JSON.parse(e.data);
    handleWsEvent(data);
  };
  ws.onclose = () => {
    wsReconnectTimer = setTimeout(connectWs, 3000);
  };
}

function scheduleRefresh() {
  if (!refreshPromise) {
    refreshPromise = refreshState().finally(() => {
      refreshPromise = null;
    });
  }
  return refreshPromise;
}

function handleWsEvent(data) {
  if (data.type === 'phase_changed') {
    showPhaseBanner(data.phaseLabel || data.phase);
    scheduleRefresh();
  } else if (data.type === 'clue_drawn' && data.playerId === playerId) {
    showToast(`手がかりを取得: ${data.clue.title}`);
    scheduleRefresh();
  } else if (data.type === 'clue_revealed') {
    showToast(`手がかりが公開されました: ${data.clue.title}`);
    scheduleRefresh();
  } else if (data.type === 'clue_transferred') {
    if (data.to === playerId) {
      showToast('手がかりを受け取りました');
    } else if (data.from === playerId) {
      showToast('手がかりを譲渡しました');
    }
    scheduleRefresh();
  } else if (data.type === 'whisper_received') {
    const cluePart = data.clue ? ` [${data.clue.title}]` : '';
    showToast(`密談: ${data.fromNickname}${cluePart}`);
    scheduleRefresh();
  } else if (data.type === 'player_left') {
    showToast(`${data.player.nickname} が切断しました`);
    scheduleRefresh();
  } else if (data.type === 'player_reconnected') {
    showToast(`${data.player.nickname} が再接続しました`);
    scheduleRefresh();
  } else if (data.type === 'character_selected' || data.type === 'player_joined') {
    scheduleRefresh();
  } else if (data.type === 'player_ready') {
    if (data.readyCount < data.totalCount) {
      showToast(`準備完了 ${data.readyCount}/${data.totalCount}`);
    }
    scheduleRefresh();
  } else if (data.type === 'truth_revealed') {
    renderTruth(data.truth, data.epilogue);
    showScreen('truth');
  } else if (data.type === 'results') {
    renderResults(data.scores, data.culpritId, data.gameMode);
    showScreen('results');
  }
}

async function refreshState() {
  if (!token) return;
  state = await api('GET', '/api/players/me');
  renderState();
}

function formatTimeRemaining(timeoutAt) {
  if (!timeoutAt) return null;
  const diff = Math.max(0, Math.floor((new Date(timeoutAt) - Date.now()) / 1000));
  const m = Math.floor(diff / 60);
  const s = diff % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function startPhaseTimer(timeoutAt, elementId) {
  if (timerInterval) clearInterval(timerInterval);
  const el = document.getElementById(elementId);
  if (!el || !timeoutAt) {
    if (el) el.classList.add('hidden');
    return;
  }

  function tick() {
    const remaining = formatTimeRemaining(timeoutAt);
    if (remaining === null || remaining === '0:00') {
      el.textContent = '0:00';
      return;
    }
    el.textContent = `残り ${remaining}`;
    el.classList.remove('hidden');
  }

  tick();
  timerInterval = setInterval(tick, 1000);
}

function renderState() {
  const { session, player, character, availableCharacters, handClues, publicClues, players, otherPlayers, whispers } = state;
  if (!session) return;

  const phase = session.phase;

  if (!session.isStarted) {
    showScreen('waiting');
    updateStatusBar('waiting');
    renderPlayerList(players);
    const charName = character?.name;
    document.getElementById('waiting-msg').textContent = charName
      ? `あなたの配役: ${charName}。ゲーム開始を待っています...`
      : '配役を割り当て中...';
    return;
  }

  const screenId = phaseScreens[phase] || 'waiting';
  showScreen(screenId);
  updateStatusBar(phase, session.phaseTimeoutAt);

  if (phase === 'synopsis') {
    document.getElementById('synopsis-text').textContent = session.synopsis;
    updateReadyButton('synopsis', player.readyFlags?.synopsis);
  } else if (phase === 'private_reading' && character) {
    renderScript(character);
    updateReadyButton('private_reading', player.readyFlags?.private_reading);
  } else if (phase === 'investigation') {
    const isCoop = session.gameMode === 'cooperative';
    const tokens = isCoop ? session.sharedTokensRemaining : player.tokensRemaining;
    document.getElementById('tokens-display').textContent =
      isCoop ? `共有トークン: ${tokens}` : `トークン: ${tokens}`;
    renderClues('hand-clues', handClues, true, otherPlayers);
    renderClues('public-clues', publicClues, false);
    renderWhisperForm(otherPlayers, handClues);
    renderWhispers(whispers, otherPlayers);
  } else if (phase === 'discussion') {
    startPhaseTimer(session.phaseTimeoutAt, 'discussion-timer');
    renderClues('discussion-clues', publicClues, false);
  } else if (phase === 'voting') {
    renderVoteList(state.characters);
  } else if (phase === 'truth_reveal' || phase === 'epilogue') {
    if (session.truth) renderTruth(session.truth, session.epilogue);
  }
}

function renderPlayerList(players) {
  const ul = document.getElementById('player-list');
  ul.innerHTML = (players || []).map(p => {
    const disconnected = p.connectionStatus === 'disconnected';
    const charStatus = p.characterName
      ? `<span class="status-ok">配役: ${p.characterName}</span>`
      : '<span class="status-wait">配役待ち...</span>';
    return `<li><span>${p.nickname}${disconnected ? ' 🔴' : ''}</span>${charStatus}</li>`;
  }).join('') || '<li class="empty-state">まだ参加者がいません</li>';
}

function renderCharacters(chars) {
  const el = document.getElementById('character-list');
  el.innerHTML = (chars || []).map(c => `
    <div class="character-card" onclick="selectCharacter('${c.id}')">
      <h3>${c.name}</h3>
      <div class="meta">${c.age}歳 / ${c.occupation}</div>
      <p>${c.publicProfile}</p>
    </div>
  `).join('');
}

async function selectCharacter(id) {
  const res = await api('POST', '/api/players/character', { characterId: id });
  if (res.error) return showToast(res.error);
  await refreshState();
}

function renderScript(char) {
  const ps = char.privateScript;
  document.getElementById('script-content').innerHTML = `
    <div class="script-section"><h3>役割</h3><p>${ps.role}</p></div>
    <div class="script-section"><h3>関係</h3><p>${ps.relationship}</p></div>
    <div class="script-section"><h3>秘密</h3><ul>${ps.secrets.map(s=>`<li>${s}</li>`).join('')}</ul></div>
    <div class="script-section"><h3>ついてよい嘘</h3><ul>${ps.allowedLies.map(s=>`<li>${s}</li>`).join('')}</ul></div>
    <div class="script-section"><h3>動機</h3><p>${ps.motive}</p></div>
    <div class="script-section"><h3>アリバイ</h3><p>${ps.alibi}</p></div>
    <div class="script-section"><h3>目標</h3><ul>${ps.objectives.map(s=>`<li>${s}</li>`).join('')}</ul></div>
  `;
}

function renderClues(containerId, clues, showActions, otherPlayers) {
  const el = document.getElementById(containerId);
  el.innerHTML = (clues || []).map(c => {
    const impLabel = importanceLabels[c.importance] || '';
    const impBadge = impLabel
      ? `<span class="importance-badge ${c.importance}">${impLabel}</span>`
      : '';
    const transferBtns = showActions && otherPlayers && otherPlayers.length
      ? otherPlayers.map(p =>
          `<button class="btn secondary btn-sm" onclick="transferClue('${c.id}','${p.id}')">${p.nickname}へ</button>`
        ).join('')
      : '';
    return `
      <div class="clue-card ${c.importance}">
        ${impBadge}
        <h4>${c.title}</h4>
        <p>${c.content}</p>
        ${showActions ? `
          <div class="clue-actions">
            <button class="btn secondary btn-sm" onclick="revealClue('${c.id}')">全員に公開</button>
            ${transferBtns}
          </div>
        ` : ''}
      </div>
    `;
  }).join('') || '<p class="empty-state">手がかりはまだありません</p>';
}

function renderWhisperForm(otherPlayers, handClues) {
  const targetEl = document.getElementById('whisper-target');
  const clueEl = document.getElementById('whisper-clue');
  if (!targetEl || !clueEl) return;

  targetEl.innerHTML = (otherPlayers || []).map(p =>
    `<option value="${p.id}">${p.nickname}</option>`
  ).join('') || '<option value="">相手なし</option>';

  const currentClue = clueEl.value;
  clueEl.innerHTML = '<option value="">なし</option>' +
    (handClues || []).map(c =>
      `<option value="${c.id}">${c.title}</option>`
    ).join('');
  if (currentClue && handClues?.some(c => c.id === currentClue)) {
    clueEl.value = currentClue;
  }
}

function renderWhispers(whispers, otherPlayers) {
  const el = document.getElementById('whispers-received');
  if (!el) return;
  const nameMap = Object.fromEntries((otherPlayers || []).map(p => [p.id, p.nickname]));
  el.innerHTML = (whispers || []).length ? `
    <div class="section-title">受信した密談</div>
    ${whispers.map(w => `
      <div class="whisper-card">
        <div class="whisper-from">From: ${nameMap[w.fromPlayerId] || '不明'}</div>
        ${w.clueId ? `<div class="whisper-clue">手がかり参照あり</div>` : ''}
        <p>${w.message}</p>
      </div>
    `).join('')}
  ` : '';
}

function renderVoteList(characters) {
  const el = document.getElementById('vote-list');
  el.innerHTML = (characters || []).map(c => `
    <div class="character-card" onclick="vote('${c.id}')">
      <h3>${c.name}${c.isNpc ? ' <span style="font-size:0.75rem;color:#888">(容疑者)</span>' : ''}</h3>
      <div class="meta">${c.occupation}</div>
    </div>
  `).join('');
}

function renderTruth(truth, epilogue) {
  document.getElementById('truth-content').innerHTML = `
    <div class="script-section"><h3>事件</h3><p>${truth.crimeDescription}</p></div>
    <div class="script-section"><h3>手法</h3><p>${truth.method}</p></div>
    <div class="script-section"><h3>動機</h3><p>${truth.motive}</p></div>
    <div class="script-section"><h3>解説</h3><p>${truth.explanation}</p></div>
    ${epilogue ? `<div class="script-section"><h3>後日談</h3><p>${epilogue}</p></div>` : ''}
  `;
}

function renderResults(scores, culpritId, gameMode) {
  const isCoop = gameMode === 'cooperative';
  const teamScore = scores && scores[0] ? scores[0].totalScore : 0;
  const teamCorrect = scores && scores[0] ? scores[0].voteCorrect : false;
  document.getElementById('results-content').innerHTML = isCoop ? `
    <p class="subtitle" style="margin-bottom:12px">
      ${teamCorrect ? '🎉 チーム成功！' : '❌ チーム失敗'}
    </p>
    <p class="subtitle" style="margin-bottom:12px">犯人ID: ${culpritId}</p>
    <div class="score-item winner">
      <span>チームスコア</span>
      <span>${teamScore}点</span>
    </div>
    ${(scores||[]).map(s => `
      <div class="score-item">
        <span>${s.nickname}（発見手がかり: ${s.cluesFound}）</span>
      </div>
    `).join('')}
  ` : `
    <p class="subtitle" style="margin-bottom:12px">犯人: ${culpritId}</p>
    ${(scores||[]).map(s => `
      <div class="score-item ${s.voteCorrect ? 'winner' : ''}">
        <span>${s.nickname}</span>
        <span>${s.totalScore}点 ${s.voteCorrect ? '✓正解' : ''}</span>
      </div>
    `).join('')}
  `;
}

function updateReadyButton(phase, isReady) {
  const btnId = phase === 'synopsis' ? 'btn-synopsis-ready' : 'btn-script-ready';
  const btn = document.getElementById(btnId);
  if (!btn) return;
  if (isReady) {
    btn.disabled = true;
    btn.textContent = '確認済み（他の参加者を待っています）';
  } else {
    btn.disabled = false;
    btn.textContent = phase === 'synopsis' ? '確認しました' : '読了しました';
  }
}

async function join() {
  const nickname = document.getElementById('nickname').value.trim();
  if (!nickname) return showToast('ニックネームを入力してください');
  const res = await api('POST', '/api/players/join', {
    nickname,
    deviceId: getDeviceId(),
  });
  if (res.error) return showToast(res.error);
  token = res.token;
  playerId = res.playerId;
  localStorage.setItem('madamis_token', token);
  localStorage.setItem('madamis_playerId', playerId);
  if (res.reconnected) showToast('この端末は既に参加済みです。再接続しました');
  connectWs();
  await refreshState();
}

async function markReady(phase) {
  const res = await api('POST', '/api/game/ready', { phase });
  if (res.error) return showToast(res.error);
  showToast('準備完了！');
  await refreshState();
}

async function drawClue() {
  const res = await api('POST', '/api/game/clue/draw');
  if (res.error) showToast(res.error);
  else await refreshState();
}

async function revealClue(clueId) {
  const res = await api('POST', '/api/game/clue/reveal', { clueId });
  if (res.error) showToast(res.error);
  else await refreshState();
}

async function transferClue(clueId, toPlayerId) {
  const res = await api('POST', '/api/game/clue/transfer', { clueId, toPlayerId });
  if (res.error) showToast(res.error);
  else await refreshState();
}

async function sendWhisper() {
  const toPlayerId = document.getElementById('whisper-target').value;
  const clueId = document.getElementById('whisper-clue').value || null;
  const message = document.getElementById('whisper-message').value.trim();
  if (!toPlayerId) return showToast('相手を選んでください');
  if (!message && !clueId) return showToast('メッセージまたは手がかりを指定してください');
  const res = await api('POST', '/api/game/whisper', { toPlayerId, clueId, message });
  if (res.error) showToast(res.error);
  else {
    document.getElementById('whisper-message').value = '';
    showToast('密談を送りました');
    await refreshState();
  }
}

async function vote(targetCharacterId) {
  const res = await api('POST', '/api/game/vote', { targetCharacterId });
  if (res.error) showToast(res.error);
  else {
    showToast('投票しました');
    await refreshState();
  }
}

async function accuse() {
  const content = document.getElementById('accusation-text').value.trim();
  const res = await api('POST', '/api/game/accuse', { content });
  if (res.error) return showToast(res.error);
  showToast('推理を発表しました');
  await refreshState();
}

document.getElementById('btn-join').addEventListener('click', join);
document.getElementById('btn-synopsis-ready').addEventListener('click', () => markReady('synopsis'));
document.getElementById('btn-script-ready').addEventListener('click', () => markReady('private_reading'));
document.getElementById('btn-draw').addEventListener('click', drawClue);
document.getElementById('btn-accuse').addEventListener('click', accuse);
document.getElementById('btn-whisper').addEventListener('click', sendWhisper);

// WebView テスト API:
// - click* … Puppeteer/Chrome 向け（Promise を await できる）
// - kick* … Android WebView 向け（非同期開始のみ。Dart 側で pumpRefresh + ポーリング）
window.__madamisTest = {
  setNickname(value) {
    const el = document.getElementById('nickname');
    if (el) el.value = value;
  },
  async clickJoin(nickname) {
    this.setNickname(nickname || 'SimPlayer');
    await join();
    return this.getState();
  },
  async clickSynopsisReady() {
    await markReady('synopsis');
    return this.getState();
  },
  async clickScriptReady() {
    await markReady('private_reading');
    return this.getState();
  },
  async clickDraw() {
    await drawClue();
    return this.getState();
  },
  async clickAccuse(text) {
    const el = document.getElementById('accusation-text');
    if (el) el.value = text || 'テスト推理';
    await accuse();
    return this.getState();
  },
  async clickWhisper(message) {
    const el = document.getElementById('whisper-message');
    if (el && message) {
      el.value = message;
    } else if (el && !el.value.trim()) {
      el.value = 'テスト密談';
    }
    await sendWhisper();
    return this.getState();
  },
  async clickRevealFirstClue() {
    const clueId = state?.handClues?.[0]?.id;
    if (!clueId) throw new Error('no hand clue to reveal');
    await revealClue(clueId);
    return this.getState();
  },
  async clickTransferFirstClue() {
    const clueId = state?.handClues?.[0]?.id;
    const toPlayerId = state?.otherPlayers?.[0]?.id;
    if (!clueId || !toPlayerId) throw new Error('no clue or transfer target');
    await transferClue(clueId, toPlayerId);
    return this.getState();
  },
  async clickVoteFirst() {
    const targetId = state?.characters?.[0]?.id;
    if (!targetId) throw new Error('no vote target');
    await vote(targetId);
    return this.getState();
  },
  handClueCount() {
    return state?.handClues?.length ?? 0;
  },
  publicClueCount() {
    return state?.publicClues?.length ?? 0;
  },
  sentWhisperCount() {
    return state?.player?.sentWhispersCount ?? 0;
  },
  hasAccused() {
    return !!state?.player?.hasAccused;
  },
  hasVoted() {
    return !!state?.player?.hasVoted;
  },
  getActiveScreen() {
    return document.querySelector('.screen.active')?.id || null;
  },
  isButtonDisabled(id) {
    return !!document.getElementById(id)?.disabled;
  },
  getState() {
    return {
      activeScreen: this.getActiveScreen(),
      phase: state?.session?.phase || null,
      token: token || null,
      playerId: playerId || null,
    };
  },
  getStateJson() {
    return JSON.stringify(this.getState());
  },
  prepareSession(nextToken, nextPlayerId) {
    token = nextToken;
    playerId = nextPlayerId;
    localStorage.setItem('madamis_token', token);
    localStorage.setItem('madamis_playerId', playerId);
    connectWs();
    scheduleRefresh();
    return 'ok';
  },
  pumpRefresh() {
    scheduleRefresh();
    return this.getActiveScreen();
  },
  kickJoin(nickname) {
    this.setNickname(nickname || 'SimPlayer');
    join();
    return 'started';
  },
  kickSynopsisReady() {
    markReady('synopsis');
    return 'started';
  },
  kickScriptReady() {
    markReady('private_reading');
    return 'started';
  },
  kickDraw() {
    drawClue();
    return 'started';
  },
  kickRevealFirstClue() {
    const clueId = state?.handClues?.[0]?.id;
    if (!clueId) throw new Error('no hand clue to reveal');
    revealClue(clueId);
    return 'started';
  },
  kickTransferFirstClue() {
    const clueId = state?.handClues?.[0]?.id;
    const toPlayerId = state?.otherPlayers?.[0]?.id;
    if (!clueId || !toPlayerId) throw new Error('no clue or transfer target');
    transferClue(clueId, toPlayerId);
    return 'started';
  },
  kickWhisper(message) {
    const el = document.getElementById('whisper-message');
    if (el && message) {
      el.value = message;
    } else if (el && !el.value.trim()) {
      el.value = 'テスト密談';
    }
    sendWhisper();
    return 'started';
  },
  kickAccuse(text) {
    const el = document.getElementById('accusation-text');
    if (el) el.value = text || 'テスト推理';
    accuse();
    return 'started';
  },
  kickVoteFirst() {
    const targetId = state?.characters?.[0]?.id;
    if (!targetId) throw new Error('no vote target');
    vote(targetId);
    return 'started';
  },
  async injectSession(nextToken, nextPlayerId) {
    token = nextToken;
    playerId = nextPlayerId;
    localStorage.setItem('madamis_token', token);
    localStorage.setItem('madamis_playerId', playerId);
    connectWs();
    await refreshState();
    return this.getState();
  },
};

if (token) {
  connectWs();
  refreshState();
}
