import puppeteer from 'puppeteer-core';

const baseUrl = process.argv[2];
if (!baseUrl) {
  console.error('Usage: node webview_headless_check.mjs <baseUrl> <json-config> [step]');
  process.exit(1);
}

const config = JSON.parse(process.argv[3] ?? '{}');
const stepArg = process.argv[4] ?? 'all';

async function waitForScreen(page, screenId, label) {
  for (let i = 0; i < 40; i++) {
    const active = await page.evaluate(() => window.__madamisTest.getActiveScreen());
    if (active === screenId) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  const active = await page.evaluate(() => window.__madamisTest.getActiveScreen());
  throw new Error(`${label}: expected ${screenId}, got ${active}`);
}

async function waitForHandClueCount(page, expected) {
  for (let i = 0; i < 40; i++) {
    const count = await page.evaluate(() => window.__madamisTest.handClueCount());
    if (count === expected) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`expected ${expected} hand clues`);
}

async function waitForPublicClueCount(page, expected) {
  for (let i = 0; i < 40; i++) {
    const count = await page.evaluate(() => window.__madamisTest.publicClueCount());
    if (count === expected) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`expected ${expected} public clues`);
}

async function runStep(label, fn) {
  const started = Date.now();
  try {
    await fn();
    console.log(`OK ${label} (${Date.now() - started}ms)`);
  } catch (err) {
    console.error(`FAIL ${label}: ${err.message}`);
    process.exitCode = 1;
    throw err;
  }
}

async function loadTestPage(page, deviceId) {
  await page.goto(`${baseUrl}/join?deviceId=${deviceId}&fresh=1`, {
    waitUntil: 'domcontentloaded',
  });
  await page.waitForFunction(() => typeof window.__madamisTest !== 'undefined', {
    timeout: 15000,
  });
}

async function injectP1(page) {
  await page.evaluate(async (token, playerId) => {
    await window.__madamisTest.injectSession(token, playerId);
  }, config.p1.token, config.p1.playerId);
}

const steps = {
  async join(page) {
    await runStep('WebView: 参加する', async () => {
      await loadTestPage(page, 'wv-sim-1');
      await page.evaluate(async () => {
        await window.__madamisTest.clickJoin('WebViewPlayer1');
      });
      await waitForScreen(page, 'screen-waiting', 'WebView: 参加する');
    });
  },
  async synopsis(page) {
    await runStep('WebView: 確認しました', async () => {
      await loadTestPage(page, 'wv-synopsis-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-synopsis', 'WebView: 確認しました');
      await page.evaluate(async () => {
        await window.__madamisTest.clickSynopsisReady();
      });
    });
  },
  async script(page) {
    await runStep('WebView: 読了しました', async () => {
      await loadTestPage(page, 'wv-script-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-script', 'WebView: 読了しました');
      await page.evaluate(async () => {
        await window.__madamisTest.clickScriptReady();
      });
    });
  },
  async draw(page) {
    await runStep('WebView: 手がかりを引く', async () => {
      await loadTestPage(page, 'wv-draw-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-investigation', 'WebView: 手がかりを引く');
      const before = await page.evaluate(() => window.__madamisTest.handClueCount());
      await page.evaluate(async () => {
        await window.__madamisTest.clickDraw();
      });
      await waitForHandClueCount(page, before + 1);
    });
  },
  async reveal(page) {
    await runStep('WebView: 全員に公開', async () => {
      await loadTestPage(page, 'wv-reveal-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-investigation', 'WebView: 全員に公開');
      if (await page.evaluate(() => window.__madamisTest.handClueCount()) === 0) {
        await page.evaluate(async () => {
          await window.__madamisTest.clickDraw();
        });
        await waitForHandClueCount(page, 1);
      }
      const publicBefore = await page.evaluate(() => window.__madamisTest.publicClueCount());
      await page.evaluate(async () => {
        await window.__madamisTest.clickRevealFirstClue();
      });
      await waitForPublicClueCount(page, publicBefore + 1);
    });
  },
  async transfer(page) {
    await runStep('WebView: 手がかり譲渡', async () => {
      await loadTestPage(page, 'wv-transfer-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-investigation', 'WebView: 手がかり譲渡');
      if (await page.evaluate(() => window.__madamisTest.handClueCount()) === 0) {
        await page.evaluate(async () => {
          await window.__madamisTest.clickDraw();
        });
        await waitForHandClueCount(page, 1);
      }
      const before = await page.evaluate(() => window.__madamisTest.handClueCount());
      await page.evaluate(async () => {
        await window.__madamisTest.clickTransferFirstClue();
      });
      await waitForHandClueCount(page, before - 1);
    });
  },
  async whisper(page) {
    await runStep('WebView: 密談を送る', async () => {
      await loadTestPage(page, 'wv-whisper-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-investigation', 'WebView: 密談を送る');
      await page.evaluate(async () => {
        await window.__madamisTest.clickWhisper('WebView密談テスト');
      });
    });
  },
  async accuse(page) {
    await runStep('WebView: 推理発表', async () => {
      await loadTestPage(page, 'wv-acc-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-accusation', 'WebView: 推理発表');
      await page.evaluate(async () => {
        await window.__madamisTest.clickAccuse('WebView推理');
      });
    });
  },
  async vote(page) {
    await runStep('WebView: 投票', async () => {
      await loadTestPage(page, 'wv-vote-1');
      await injectP1(page);
      await waitForScreen(page, 'screen-voting', 'WebView: 投票');
      await page.evaluate(async () => {
        await window.__madamisTest.clickVoteFirst();
      });
    });
  },
};

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox'],
});

try {
  const page = await browser.newPage();
  const allSteps = ['join', 'synopsis', 'script', 'draw', 'reveal', 'transfer', 'whisper', 'accuse', 'vote'];
  if (stepArg === 'all') {
    for (const step of allSteps) {
      await steps[step](page);
    }
  } else if (steps[stepArg]) {
    await steps[stepArg](page);
  } else {
    throw new Error(`Unknown step: ${stepArg}`);
  }
} finally {
  await browser.close();
}
