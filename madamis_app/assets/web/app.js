const API = '';
let token = localStorage.getItem('madamis_token') || '';
let playerId = localStorage.getItem('madamis_playerId') || '';
let ws = null;
let state = {};

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

function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onopen = () => {
    ws.send(JSON.stringify({ type: 'auth', token }));
    setInterval(() => ws.send(JSON.stringify({ type: 'ping' })), 30000);
  };
  ws.onmessage = (e) => {
    const data = JSON.parse(e.data);
    handleWsEvent(data);
  };
  ws.onclose = () => setTimeout(connectWs, 3000);
}

function handleWsEvent(data) {
  if (data.type === 'phase_changed') {
    showPhaseBanner(data.phaseLabel || data.phase);
    refreshState();
  } else if (data.type === 'clue_drawn' && data.playerId === playerId) {
    showToast(`手がかりを取得: ${data.clue.title}`);
    refreshState();
  } else if (data.type === 'clue_revealed') {
    showToast(`手がかりが公開されました: ${data.clue.title}`);
    refreshState();
  } else if (data.type === 'character_selected' || data.type === 'player_joined') {
    refreshState();
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

function renderState() {
  const { session, player, character, availableCharacters, handClues, publicClues, players } = state;
  if (!session) return;

  const phase = session.phase;

  if (!session.isStarted) {
    if (player.characterId) {
      showScreen('waiting');
      renderPlayerList(players);
      document.getElementById('waiting-msg').textContent = 'ゲーム開始を待っています...';
    } else {
      showScreen('character');
      renderCharacters(availableCharacters);
    }
    return;
  }

  const screenId = phaseScreens[phase] || 'waiting';
  showScreen(screenId);

  if (phase === 'synopsis') {
    document.getElementById('synopsis-text').textContent = session.synopsis;
  } else if (phase === 'private_reading' && character) {
    renderScript(character);
  } else if (phase === 'investigation') {
    const isCoop = session.gameMode === 'cooperative';
    const tokens = isCoop ? session.sharedTokensRemaining : player.tokensRemaining;
    document.getElementById('tokens-display').textContent =
      isCoop ? `共有トークン: ${tokens}` : `トークン: ${tokens}`;
    renderClues('hand-clues', handClues, true);
    renderClues('public-clues', publicClues, false);
  } else if (phase === 'voting') {
    renderVoteList(state.characters);
  } else if (phase === 'truth_reveal' || phase === 'epilogue') {
    if (session.truth) renderTruth(session.truth, session.epilogue);
  }
}

function renderPlayerList(players) {
  const ul = document.getElementById('player-list');
  ul.innerHTML = (players || []).map(p =>
    `<li><span>${p.nickname}</span><span>${p.characterId ? '✓ 配役済' : '選択中...'}</span></li>`
  ).join('');
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
  await api('POST', '/api/players/character', { characterId: id });
  refreshState();
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

function renderClues(containerId, clues, showActions) {
  const el = document.getElementById(containerId);
  el.innerHTML = (clues || []).map(c => `
    <div class="clue-card ${c.importance}">
      <h4>${c.title}</h4>
      <p>${c.content}</p>
      ${showActions ? `<button class="btn secondary" onclick="revealClue('${c.id}')">全員公開</button>` : ''}
    </div>
  `).join('') || '<p class="hint">手がかりなし</p>';
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

async function join() {
  const nickname = document.getElementById('nickname').value.trim();
  if (!nickname) return showToast('ニックネームを入力してください');
  const res = await api('POST', '/api/players/join', { nickname });
  if (res.error) return showToast(res.error);
  token = res.token;
  playerId = res.playerId;
  localStorage.setItem('madamis_token', token);
  localStorage.setItem('madamis_playerId', playerId);
  connectWs();
  refreshState();
}

async function markReady(phase) {
  await api('POST', '/api/game/ready', { phase });
  showToast('準備完了！');
}

async function drawClue() {
  const res = await api('POST', '/api/game/clue/draw');
  if (res.error) showToast(res.error);
  else refreshState();
}

async function revealClue(clueId) {
  await api('POST', '/api/game/clue/reveal', { clueId });
  refreshState();
}

async function vote(targetCharacterId) {
  const res = await api('POST', '/api/game/vote', { targetCharacterId });
  if (res.error) showToast(res.error);
  else showToast('投票しました');
}

async function accuse() {
  const content = document.getElementById('accusation-text').value.trim();
  await api('POST', '/api/game/accuse', { content });
  showToast('推理を発表しました');
}

document.getElementById('btn-join').addEventListener('click', join);
document.getElementById('btn-synopsis-ready').addEventListener('click', () => markReady('synopsis'));
document.getElementById('btn-script-ready').addEventListener('click', () => markReady('private_reading'));
document.getElementById('btn-draw').addEventListener('click', drawClue);
document.getElementById('btn-accuse').addEventListener('click', accuse);

if (token) {
  connectWs();
  refreshState();
}
