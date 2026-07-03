# マダミス自動進行アプリ 詳細設計書

## 1. 概要

TOTEM型の対面マーダーミステリーを、Androidタブレット（Flutter）を親機として提供する。
プレイヤーはブラウザでQR参加し、AI（Gemini）が生成したシナリオを自動進行でプレイする。

### 1.1 確定要件

| 項目 | 内容 |
|------|------|
| 親機 | Androidタブレット（Flutter）+ WiFiホットスポット |
| 参加者 | ブラウザ（Android/iPhone/PC）、アプリ不要 |
| GM | 不要（タブレットが全自動進行） |
| 人数 | 2〜8人（AIが構成自動調整） |
| 少人数 | 2〜3人向け別ルール |
| ネット | 生成時のみ必須、プレイはオフライン |
| AI | Gemini、ゲーム開始前生成 |
| 品質 | 全矛盾チェック + 正解ルート検証後に完成 |
| 言語 | 日本語のみ |

---

## 2. システムアーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│                    Android Tablet (Flutter)                   │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐  │
│  │ UI Layer    │  │ Game Engine  │  │ Scenario Pipeline   │  │
│  │ (Tablet UI) │◄─┤ (State Machine│◄─┤ Generate → Validate│  │
│  └─────────────┘  │  Auto GM)    │  └──────────┬──────────┘  │
│                   └──────┬───────┘             │             │
│  ┌─────────────┐  ┌──────▼───────┐  ┌──────────▼──────────┐  │
│  │ Audio       │  │ Local Server │  │ Storage (SQLite)    │  │
│  │ (BGM/SE)    │  │ (Shelf/Dart) │  │ Scenarios/Saves     │  │
│  └─────────────┘  └──────┬───────┘  └─────────────────────┘  │
│                          │                                     │
│  ┌───────────────────────▼─────────────────────────────────┐  │
│  │ WiFi Hotspot (Android API)                               │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────┬───────────────────────────────┘
                               │ HTTP + WebSocket (LAN only)
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
         Player Browser   Player Browser   Player Browser
         (PWA-like SPA)   (PWA-like SPA)   (PWA-like SPA)

┌──────────────────────────────────────────────────────────────┐
│  Internet (Scenario Generation Phase Only)                    │
│  └─ Gemini API                                               │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 技術スタック

| レイヤー | 技術 |
|---------|------|
| 親機アプリ | Flutter (Dart 3.x) |
| 親機内Webサーバー | `shelf` + `shelf_web_socket` |
| プレイヤーUI | HTML/CSS/JS（親機から静的配信） |
| リアルタイム通信 | WebSocket |
| 永続化 | SQLite (`sqflite`) |
| AI | Google Gemini API (`google_generative_ai`) |
| 音声 | `audioplayers` |
| WiFi AP | `wifi_iot` または Platform Channel |

### 2.2 ネットワーク構成

| 項目 | 値 |
|------|-----|
| 親機IP | `192.168.43.1`（Android Hotspot デフォルト） |
| HTTP | `:8080` |
| WebSocket | `:8080/ws` |
| QR内容 | `http://192.168.43.1:8080/join?room={roomId}` |

---

## 3. 画面一覧

### 3.1 タブレット（親機）画面

| # | 画面ID | 名称 | 説明 |
|---|--------|------|------|
| T1 | `tablet_home` | ホーム | 新規ゲーム / 続きから / 設定 |
| T2 | `tablet_hotspot` | ホットスポット設定 | AP起動状態、SSID表示、接続数 |
| T3 | `tablet_scenario_config` | シナリオ設定 | ジャンル・難易度・時間・人数・テーマ入力 |
| T4 | `tablet_generating` | 生成中 | AI生成 + 検証進捗（ステップ表示） |
| T5 | `tablet_lobby` | ロビー | QRコード大表示、参加プレイヤー一覧 |
| T6 | `tablet_game_dashboard` | ゲームダッシュボード | 現在フェーズ、タイマー、全員状態 |
| T7 | `tablet_phase_overlay` | フェーズ通知 | フェーズ遷移時の全画面表示（自動） |
| T8 | `tablet_truth` | 真相発表 | 真相・後日談・結果（タブレットにも表示） |
| T9 | `tablet_settings` | 設定 | Gemini APIキー、音量、ホットスポット設定 |
| T10 | `tablet_save_list` | セーブ一覧 | 中断セーブの一覧・再開 |

#### T3 シナリオ設定 入力項目

| 項目 | UI | 選択肢 / 制約 |
|------|-----|--------------|
| ジャンル | ドロップダウン | 洋館、現代、和風、ホラー、ファンタジー、ミステリー |
| 難易度 | 3段階スライダー | 初級 / 中級 / 上級 |
| プレイ時間 | スライダー | 30 / 60 / 90 / 120 分 |
| 参加人数 | 数値入力 | 2〜8 |
| テーマ | 自由入力 | 最大100文字（例：「雪山の別荘」「結婚式の夜」） |

#### T4 生成中 進捗ステップ

```
[1/6] 世界観・事件設定を生成中...
[2/6] 登場人物・役割を生成中...
[3/6] 台本・手がかりを生成中...
[4/6] 整合性チェック中...
[5/6] 正解ルート検証中...
[6/6] シナリオ完成！
```

---

### 3.2 プレイヤー（ブラウザ）画面

| # | 画面ID | 名称 | 説明 |
|---|--------|------|------|
| P1 | `player_join` | 参加 | ニックネーム入力、ルーム参加 |
| P2 | `player_waiting` | 待機 | 他プレイヤー待ち、接続状態表示 |
| P3 | `player_character_select` | 配役選択 | キャラクター一覧から選択 |
| P4 | `player_synopsis` | あらすじ | 共通あらすじ表示（全員同時） |
| P5 | `player_script` | 個人台本 | 役割・秘密・嘘・動機（黙読） |
| P6 | `player_investigation` | 調査 | トークン操作、手がかり管理 |
| P7 | `player_discussion` | 議論 | 議論フェーズ（タイマー表示） |
| P8 | `player_accusation` | 推理発表 | 推理内容入力（任意） |
| P9 | `player_vote` | 投票 | 犯人指名投票 |
| P10 | `player_truth` | 真相 | 真相解説・後日談 |
| P11 | `player_result` | 結果 | 得点・正解/不正解 |

#### P6 調査画面 操作一覧

| 操作 | 説明 | トークン消費 |
|------|------|-------------|
| 手がかりを引く | 山札から1枚取得 | 1 |
| 手がかりを譲渡 | 他プレイヤーに渡す | 0 |
| 全員公開 | 手がかりを全員に公開 | 0 |
| 密談 | 1対1で情報共有（相手のみ閲覧） | 0 |

---

## 4. ゲーム進行ステートマシン

### 4.1 フェーズ定義

```
LOBBY
  │ 全員参加 + 配役完了 + ホスト(タブレット)スタート
  ▼
SYNOPSIS          ── 共通あらすじ表示（60秒 or 全員タップ）
  ▼
PRIVATE_READING   ── 個人台本黙読（120秒 or 全員「読了」）
  ▼
INVESTIGATION     ── 調査フェーズ（トークン制、時間制限あり）
  ▼
DISCUSSION        ── 自由議論（タイマー）
  ▼
ACCUSATION        ── 推理発表（任意、順番 or 自由）
  ▼
VOTING            ── 犯人投票
  ▼
TRUTH_REVEAL      ── 真相解説
  ▼
EPILOGUE          ── 後日談
  ▼
RESULTS           ── 得点発表・結果
  ▼
END
```

### 4.2 フェーズ遷移条件

| フェーズ | 自動遷移条件 | タイムアウト |
|---------|-------------|-------------|
| SYNOPSIS | 全員「確認」タップ | 60秒 |
| PRIVATE_READING | 全員「読了」タップ | 180秒 |
| INVESTIGATION | タイマー終了 or 全員「議論へ」 | 設定時間の40% |
| DISCUSSION | タイマー終了 | 設定時間の35% |
| ACCUSATION | 全員発表完了 or スキップ | 60秒 |
| VOTING | 全員投票完了 | 120秒 |
| TRUTH_REVEAL | 自動（30秒表示後） | 30秒 |
| EPILOGUE | 自動（30秒表示後） | 30秒 |
| RESULTS | タブレット「終了」 | - |

### 4.3 少人数モード（2〜3人）差分

| 項目 | 通常（4〜8人） | 少人数（2〜3人） |
|------|--------------|----------------|
| モード名 | 対立推理 | 協力推理 |
| 容疑者 | 全員が容疑者 | NPC容疑者をAI追加 |
| プレイヤー役割 | 容疑者（全員犯人候補） | 探偵チーム |
| 調査トークン | 個人3枚 | 共有5枚 |
| 勝利条件 | 犯人を当てる | 全員で犯人特定 |
| 投票 | 個人投票 | 共同投票（多数決） |
| 得点 | 個人スコア | チームスコア |

---

## 5. データ構造

### 5.1 Scenario（シナリオ）

```typescript
interface Scenario {
  id: string;                    // UUID v4
  version: string;               // "1.0.0"
  metadata: ScenarioMetadata;
  synopsis: string;              // 共通あらすじ（500〜1000字）
  truth: Truth;
  characters: Character[];       // playerCount 分（少人数時はNPC含む）
  clues: Clue[];                 // 15〜30枚（人数で変動）
  phases: PhaseConfig[];         // フェーズ時間設定
  scoring: ScoringRules;
  solutionPath: SolutionPath;    // 検証用正解ルート
  audio: AudioConfig;            // BGM/SE割当
  gameMode: "competitive" | "cooperative";
}

interface ScenarioMetadata {
  title: string;
  genre: Genre;
  difficulty: "beginner" | "intermediate" | "advanced";
  estimatedMinutes: number;
  playerCount: number;
  theme: string;
  generatedAt: string;           // ISO8601
  validationPassed: boolean;
  validationReport: ValidationReport;
}

type Genre = "mansion" | "modern" | "japanese" | "horror" | "fantasy" | "mystery";
```

### 5.2 Truth（真相）

```typescript
interface Truth {
  culpritId: string;             // 犯人キャラクターID
  crime: {
    description: string;         // 何が起きたか
    method: string;              // 犯行手法
    motive: string;              // 動機
    timeOfCrime: string;         // 犯行時刻 "22:30"
    location: string;            // 犯行場所
  };
  timeline: TimelineEvent[];     // 全員の行動タイムライン
}

interface TimelineEvent {
  time: string;                  // "22:00"
  characterId: string;
  location: string;
  action: string;
  isPublic: boolean;             // プレイヤーに公開される情報か
}
```

### 5.3 Character（キャラクター）

```typescript
interface Character {
  id: string;
  name: string;
  age: number;
  gender: string;
  occupation: string;
  appearance: string;            // 外見描写
  publicProfile: string;         // 全員が知っている情報
  isPlayer: boolean;             // プレイヤーが演じるか（NPC=false）
  isSuspect: boolean;
  privateScript: PrivateScript;
}

interface PrivateScript {
  role: string;                  // 役割説明
  relationship: string;          // 他キャラとの関係
  secrets: Secret[];             // 秘密（2〜4個）
  allowedLies: AllowedLie[];     // ついてよい嘘（1〜2個）
  motive: string;                // 演じる動機（犯人以外は赤 herring も）
  alibi: {
    timeRange: string;           // "22:00-23:00"
    location: string;
    description: string;
    isTrue: boolean;             // 本当のアリバイか
  };
  objectives: string[];            // 個人目標
}

interface Secret {
  id: string;
  content: string;
  revealCondition?: string;      // 公開条件（任意）
}

interface AllowedLie {
  id: string;
  topic: string;                 // 嘘をついてよい話題
  lieContent: string;            // 嘘の内容
  truthContent: string;          // 真実（検証用、プレイヤー非表示）
}
```

### 5.4 Clue（手がかり）

```typescript
interface Clue {
  id: string;
  title: string;
  content: string;               // 手がかり本文
  type: "physical" | "testimony" | "document" | "digital";
  importance: "critical" | "important" | "supplementary";
  pointsTo: string[];            // 関連キャラクターID
  implicates: string[];          // 疑わせるキャラクターID
  location: string;              // 発見場所
  initialState: "deck" | "character"; 
  initialHolder?: string;        // character ID if not deck
  revealPhase?: GamePhase;       // 自動公開フェーズ（任意）
}

type GamePhase =
  | "lobby" | "synopsis" | "private_reading"
  | "investigation" | "discussion" | "accusation"
  | "voting" | "truth_reveal" | "epilogue" | "results";
```

### 5.5 SolutionPath（正解ルート・検証用）

```typescript
interface SolutionPath {
  requiredClues: string[];       // 犯人特定に必要な最低限の手がかりID
  deductionSteps: DeductionStep[];
  alternativePaths: string[][];  // 別解ルート（手がかりID配列）
}

interface DeductionStep {
  order: number;
  description: string;           // 「Aの証言とBの手がかりから犯行時刻が..."
  requiredClues: string[];
  eliminates: string[];          // この時点で除外できるキャラID
  conclusion?: string;           // 最終ステップで犯人特定
}
```

### 5.6 GameSession（ゲームセッション）

```typescript
interface GameSession {
  id: string;
  roomId: string;                // 4桁数字
  scenarioId: string;
  phase: GamePhase;
  phaseStartedAt: string;
  phaseTimeoutAt: string;
  players: Player[];
  clueState: ClueState;
  votes: Vote[];
  accusations: Accusation[];
  scores: Score[];
  startedAt: string;
  savedAt?: string;
  isPaused: boolean;
}

interface Player {
  id: string;
  nickname: string;
  characterId: string | null;
  connectionStatus: "connected" | "disconnected";
  lastSeenAt: string;
  tokensRemaining: number;
  handClues: string[];           // 所持手がかりID
  publicClues: string[];         // 公開した手がかりID
  readyFlags: Record<GamePhase, boolean>;
}

interface ClueState {
  deck: string[];                // 未引き手がかりID
  publicClues: string[];         // 全員公開済み
  transfers: ClueTransfer[];     // 譲渡履歴
  whispers: Whisper[];           // 密談履歴
}

interface Vote {
  playerId: string;
  targetCharacterId: string;
  timestamp: string;
}

interface Score {
  playerId: string;
  voteCorrect: boolean;          // 犯人投票正解
  objectivesCompleted: number;
  cluesFound: number;
  totalScore: number;
}
```

### 5.7 ValidationReport（検証レポート）

```typescript
interface ValidationReport {
  passed: boolean;
  attempts: number;
  checks: ValidationCheck[];
  solvabilityProof: SolvabilityProof;
}

interface ValidationCheck {
  name: string;
  passed: boolean;
  errors: string[];
}

interface SolvabilityProof {
  canReachCulprit: boolean;
  minCluesRequired: number;
  allCluesReachable: boolean;
  noContradictions: boolean;
  simulatedPlaythrough: boolean;
}
```

---

## 6. API設計

### 6.1 REST API

Base URL: `http://192.168.43.1:8080/api`

#### ルーム

| Method | Path | 説明 | Request | Response |
|--------|------|------|---------|----------|
| GET | `/room` | ルーム状態取得 | - | `RoomStatus` |
| POST | `/room/start` | ゲーム開始（タブレットのみ） | - | `GameSession` |

#### プレイヤー

| Method | Path | 説明 | Request | Response |
|--------|------|------|---------|----------|
| POST | `/players/join` | 参加 | `{ nickname }` | `{ playerId, token }` |
| POST | `/players/character` | 配役選択 | `{ characterId }` | `Player` |
| GET | `/players/me` | 自分の情報 | Header: `Authorization: Bearer {token}` | `Player` |

#### ゲーム操作

| Method | Path | 説明 | Request | Response |
|--------|------|------|---------|----------|
| POST | `/game/ready` | フェーズ完了通知 | `{ phase }` | `{ phase, allReady }` |
| POST | `/game/clue/draw` | 手がかりを引く | - | `Clue` |
| POST | `/game/clue/transfer` | 手がかり譲渡 | `{ clueId, toPlayerId }` | `ClueTransfer` |
| POST | `/game/clue/reveal` | 全員公開 | `{ clueId }` | `Clue` |
| POST | `/game/whisper` | 密談 | `{ toPlayerId, clueId, message }` | `Whisper` |
| POST | `/game/accuse` | 推理発表 | `{ content }` | `Accusation` |
| POST | `/game/vote` | 投票 | `{ targetCharacterId }` | `Vote` |

#### シナリオ（タブレットのみ）

| Method | Path | 説明 | Request | Response |
|--------|------|------|---------|----------|
| POST | `/scenario/generate` | 生成開始 | `ScenarioConfig` | `{ jobId }` |
| GET | `/scenario/generate/{jobId}` | 生成進捗 | - | `GenerationProgress` |
| GET | `/scenario/current` | 現在のシナリオ | - | `Scenario` (partial) |

#### セーブ

| Method | Path | 説明 | Request | Response |
|--------|------|------|---------|----------|
| POST | `/save` | セーブ | - | `{ saveId }` |
| GET | `/saves` | セーブ一覧 | - | `SaveSummary[]` |
| POST | `/saves/{id}/load` | ロード | - | `GameSession` |

---

### 6.2 WebSocket API

URL: `ws://192.168.43.1:8080/ws`

#### 接続

```json
// Client → Server
{ "type": "auth", "token": "player-token-or-tablet" }

// Server → Client
{ "type": "auth_ok", "role": "player|tablet", "session": GameSession }
```

#### サーバー → クライアント イベント

| type | 説明 | payload |
|------|------|---------|
| `player_joined` | プレイヤー参加 | `{ player }` |
| `player_left` | プレイヤー離脱 | `{ playerId }` |
| `player_reconnected` | 再接続 | `{ player }` |
| `character_selected` | 配役選択 | `{ playerId, characterId }` |
| `phase_changed` | フェーズ遷移 | `{ phase, timeoutAt, data? }` |
| `clue_drawn` | 手がかり取得 | `{ playerId, clue }` |
| `clue_transferred` | 手がかり譲渡 | `{ from, to, clueId }` |
| `clue_revealed` | 全員公開 | `{ playerId, clue }` |
| `whisper_received` | 密談受信 | `{ from, clueId?, message }` |
| `vote_cast` | 投票（匿名） | `{ votedCount, totalCount }` |
| `all_voted` | 全員投票完了 | `{ votes }` |
| `truth_revealed` | 真相公開 | `{ truth, epilogue }` |
| `results` | 結果発表 | `{ scores, winner }` |
| `timer_tick` | タイマー更新 | `{ remainingSeconds }` |
| `generation_progress` | 生成進捗 | `{ step, progress, message }` |

#### クライアント → サーバー イベント

| type | 説明 | payload |
|------|------|---------|
| `ready` | フェーズ完了 | `{ phase }` |
| `draw_clue` | 手がかりを引く | `{}` |
| `transfer_clue` | 譲渡 | `{ clueId, toPlayerId }` |
| `reveal_clue` | 公開 | `{ clueId }` |
| `whisper` | 密談 | `{ toPlayerId, clueId?, message }` |
| `accuse` | 推理 | `{ content }` |
| `vote` | 投票 | `{ targetCharacterId }` |
| `ping` | 接続維持 | `{}` |

---

## 7. AIシナリオ生成パイプライン

### 7.1 生成フロー

```
Input: ScenarioConfig
  │
  ├─[Step 1] generateWorldAndCrime()
  │   └─ 世界観、事件概要、犯人、動機、犯行手法、タイムライン
  │
  ├─[Step 2] generateCharacters()
  │   └─ プレイヤー数分のキャラ + 少人数時NPC
  │
  ├─[Step 3] generatePrivateScripts()
  │   └─ 各キャラの秘密、嘘、アリバイ、目標
  │
  ├─[Step 4] generateClues()
  │   └─ 手がかりカード（真相到達可能セット）
  │
  ├─[Step 5] generateSolutionPath()
  │   └─ 正解ルート・推理ステップ
  │
  ├─[Step 6] validateScenario()  ── 不合格 → Step 3-5 再生成（最大5回）
  │   └─ 全検証パス
  │
  └─ Output: Scenario (validationPassed: true)
```

### 7.2 Gemini プロンプト構成

各ステップで構造化JSON出力を要求。`responseSchema` で型を強制。

#### Step 1 プロンプト（概要）

```
あなたはマーダーミステリーのシナリオライターです。
以下の条件でシナリオの骨格を生成してください。

- ジャンル: {genre}
- 難易度: {difficulty}
- プレイ時間: {minutes}分
- 人数: {playerCount}人
- テーマ: {theme}

出力はJSON形式。犯人は必ず1人。アリバイと犯行時刻に矛盾がないこと。
```

#### Step 6 検証プロンプト（検証AI）

```
以下のシナリオJSONについて、プレイヤー視点で推理シミュレーションを行い、
犯人を特定できるか検証してください。

チェック項目:
1. 必要手がかりが全て引けるか（デッキに存在するか）
2. アリバイとタイムラインに矛盾がないか
3. 嘘をつく設定がバレても推理可能か
4. 犯人以外に動機があるキャラが十分か（赤 herring）
5. 最低限の手がかりセットで犯人に到達できるか

結果をJSON形式で返してください。
```

### 7.3 自動検証ルール（コード側）

| # | 検証名 | ロジック |
|---|--------|---------|
| V1 | `timeline_consistency` | 全キャラの timeline と alibi の時刻・場所整合 |
| V2 | `culprit_alibi_invalid` | 犯人のアリバイが犯行時刻と両立しない |
| V3 | `clue_reachability` | requiredClues が deck or 配布可能 |
| V4 | `culprit_identifiable` | solutionPath の deductionSteps で全容疑者から犯人に絞れる |
| V5 | `character_count_match` | characters.filter(isPlayer).length === playerCount |
| V6 | `clue_count_range` | 人数に応じた手がかり数（2人:10, 8人:30） |
| V7 | `lie_safety` | allowedLie がバレても alternativePaths で推理可能 |
| V8 | `motive_culprit_match` | 犯人の motive が truth.motive と一致 |
| V9 | `no_dead_end` | 全フェーズ遷移可能、トークン枯渇でも最低1手がかり取得可 |
| V10 | `ai_simulation` | Gemini にプレイスルー検証させ pass/fail |

---

## 8. 人数別パラメータ

| 人数 | モード | 容疑者 | 手がかり数 | 個人トークン | 秘密/人 | 嘘/人 |
|------|--------|--------|-----------|-------------|---------|-------|
| 2 | 協力 | 2+2NPC | 10 | 共有5 | 2 | 1 |
| 3 | 協力 | 3+1NPC | 12 | 共有6 | 2 | 1 |
| 4 | 対立 | 4 | 15 | 3 | 2 | 1 |
| 5 | 対立 | 5 | 18 | 3 | 3 | 1 |
| 6 | 対立 | 6 | 22 | 3 | 3 | 2 |
| 7 | 対立 | 7 | 26 | 3 | 3 | 2 |
| 8 | 対立 | 8 | 30 | 3 | 4 | 2 |

---

## 9. 得点システム

### 9.1 対立モード（4〜8人）

| 項目 | 点数 |
|------|------|
| 犯人投票正解 | +100 |
| 犯人投票不正解 | 0 |
| 個人目標達成 | +30 / 目標 |
| 重要手がかり発見 | +10 / 枚 |
| 推理発表ボーナス | +20（真相に近い場合） |

### 9.2 協力モード（2〜3人）

| 項目 | 点数 |
|------|------|
| 犯人特定成功 | +300（チーム全員） |
| 犯人特定失敗 | 0 |
| 重要手がかり発見 | +20 / 枚 |
| 時間ボーナス | 残り時間 × 1 |

---

## 10. 中断再開設計

### 10.1 自動セーブタイミング

- フェーズ遷移時
- 手がかり操作時
- 投票完了時
- 30秒間隔（バックグラウンド）

### 10.2 セーブデータ

```
SQLite: saves テーブル
├─ id
├─ scenario_json (TEXT)
├─ session_json (TEXT)
├─ phase (TEXT)
├─ saved_at (TEXT)
└─ thumbnail (TEXT) -- シナリオタイトル + 人数
```

### 10.3 再接続

1. プレイヤーがQR再読み込み → `playerId` を localStorage から復元
2. WebSocket再接続 → サーバーが `auth` で同一プレイヤー判定
3. 現在フェーズの状態を全送信（手がかり、投票状態含む）

---

## 11. BGM/SE設計

| フェーズ | BGM | SE |
|---------|-----|-----|
| LOBBY | `bgm_lobby.mp3` (ループ) | 参加: `se_join.mp3` |
| SYNOPSIS | `bgm_tension.mp3` | フェーズ遷移: `se_phase.mp3` |
| PRIVATE_READING | `bgm_mystery.mp3` | - |
| INVESTIGATION | `bgm_investigation.mp3` | 手がかり取得: `se_clue.mp3` |
| DISCUSSION | `bgm_discussion.mp3` | - |
| VOTING | `bgm_suspense.mp3` | 投票: `se_vote.mp3` |
| TRUTH_REVEAL | - | 真相: `se_truth.mp3` |
| RESULTS | `bgm_ending.mp3` | 正解: `se_correct.mp3` / 不正解: `se_wrong.mp3` |

---

## 12. ディレクトリ構成（Flutter）

```
lib/
├── main.dart
├── app.dart
├── config/
│   └── constants.dart
├── models/
│   ├── scenario.dart
│   ├── character.dart
│   ├── clue.dart
│   ├── game_session.dart
│   └── validation.dart
├── services/
│   ├── hotspot_service.dart
│   ├── server_service.dart       # shelf HTTP/WS
│   ├── game_engine.dart          # ステートマシン
│   ├── scenario_generator.dart   # Gemini連携
│   ├── scenario_validator.dart   # 検証エンジン
│   ├── audio_service.dart
│   └── save_service.dart
├── screens/
│   ├── home_screen.dart
│   ├── hotspot_screen.dart
│   ├── scenario_config_screen.dart
│   ├── generating_screen.dart
│   ├── lobby_screen.dart
│   ├── game_dashboard_screen.dart
│   └── settings_screen.dart
└── widgets/
    ├── qr_display.dart
    ├── player_list.dart
    ├── phase_timer.dart
    └── generation_progress.dart

assets/
├── web/                          # プレイヤー用SPA
│   ├── index.html
│   ├── css/
│   ├── js/
│   └── manifest.json
├── audio/
│   ├── bgm/
│   └── se/
└── prompts/                      # Geminiプロンプトテンプレート
    ├── step1_world.txt
    ├── step2_characters.txt
    ├── step3_scripts.txt
    ├── step4_clues.txt
    ├── step5_solution.txt
    └── step6_validate.txt
```

---

## 13. セキュリティ考慮

| 項目 | 対策 |
|------|------|
| プレイヤー認証 | 参加時に UUID トークン発行、WS接続時検証 |
| 真相漏洩 | プレイヤーAPIは `truth` フィールドを除外 |
| 手がかり秘匿 | 他プレイヤーの `handClues` は自分のみ取得可 |
| APIキー | Gemini APIキーはタブレットローカル保存（暗号化） |
| 外部アクセス | ホットスポット内のみ、インターネット非公開 |

---

## 14. 非機能要件

| 項目 | 目標 |
|------|------|
| 同時接続 | 8プレイヤー + タブレット |
| 生成時間 | 3分以内（検証含む） |
| フェーズ遷移遅延 | 500ms以内 |
| 再接続復帰 | 5秒以内 |
| 対応Android | API 26+（Android 8.0） |
| タブレット画面 | 10インチ以上推奨（1280×800） |
| プレイヤー画面 | 320px幅以上（スマホ対応） |

---

## 15. 将来拡張（商用・スコープ外）

- 収益化（サブスク / 従量課金）
- シナリオ履歴・お気に入り
- カスタムBGM
- 多言語対応
- シナリオエクスポート/インポート
- 店舗向け管理画面
