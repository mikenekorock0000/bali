import '../models/scenario.dart';

/// 2人協力推理デモ: 探偵チーム vs NPC容疑者
Scenario createCoopScenario({int playerCount = 2}) {
  return Scenario(
    id: 'coop_cafe_001',
    title: '雨夜のカフェ・マーダー',
    genre: '現代',
    playerCount: playerCount,
    gameMode: 'cooperative',
    synopsis: '''
繁華街の小さなカフェ「ミスト」で、オーナーの藤原健一が毒入りコーヒーで倒れた。
閉店後の店内にいたのは、従業員と常連客だけ。
警察はまだ到着していない。2人の探偵は現場に偶然居合わせ、
協力して事件の真相を暴くことになった。

容疑者は3人。彼らの証言は互いに矛盾している。
手がかりを共有し、議論を重ね、真犯人を特定せよ。
''',
    epilogue: '''
真犯人はマネージャーの佐藤だった。リストラ通告を受けていた彼は、
健一の保険金を狙った。探偵チームの推理により、事件は解決した。
''',
    truth: ScenarioTruth(
      culpritId: 'npc_manager',
      crimeDescription: '藤原健一を毒殺',
      method: 'コーヒーに青酸カリを混入',
      motive: 'リストラ通告と保険金',
      timeOfCrime: '21:30',
      location: 'カフェ「ミスト」厨房',
      explanation: '''
マネージャー佐藤は閉店準備中に厨房で毒を混入。
従業員の田中は厨房近くにいたが、佐藤の行動を目撃していなかった。
常連の山本はトイレにいたためアリバイがあるが、佐藤の証言と矛盾する。
決定的なのは佐藤の手袋に残った毒の痕跡と、リストラ通告のメール。
''',
    ),
    characters: [
      // プレイ偵（探偵チーム）
      ScenarioCharacter(
        id: 'char_detective_1',
        name: '探偵・赤羽',
        age: 32,
        occupation: '私立探偵',
        publicProfile: '依頼を受けて現場に来ていた探偵。',
        isPlayer: true,
        privateScript: PrivateScript(
          role: '探偵',
          relationship: '現場に偶然居合わせた',
          secrets: ['健一から別件の依頼を受けていた'],
          allowedLies: [],
          motive: '事件解決と依頼人の信頼',
          alibi: '21:00-22:00 店内の隅の席で調査',
          objectives: ['真犯人を特定する'],
        ),
      ),
      if (playerCount >= 2)
        ScenarioCharacter(
          id: 'char_detective_2',
          name: '探偵・青木',
          age: 28,
          occupation: '鑑識官',
          publicProfile: '赤羽の協力者。鑑識の知識を持つ。',
          isPlayer: true,
          privateScript: PrivateScript(
            role: '探偵',
            relationship: '赤羽のパートナー',
            secrets: ['毒物の初期分析結果を持っている'],
            allowedLies: [],
            motive: '事件解決',
            alibi: '21:00-22:00 赤羽と共に店内',
            objectives: ['科学的証拠を集める'],
          ),
        ),
      // NPC容疑者
      ScenarioCharacter(
        id: 'npc_staff',
        name: '田中ユキ',
        age: 24,
        occupation: 'カフェ店員',
        publicProfile: '従業員。事件当夜は厨房付近にいた。',
        isPlayer: false,
        privateScript: PrivateScript(
          role: '容疑者',
          relationship: '被害者の従業員',
          secrets: ['健一と給料トラブルがあった'],
          allowedLies: ['厨房にいなかったと主張してよい'],
          motive: '給料未払いへの怒り',
          alibi: '21:20-21:40 厨房で皿洗い',
          objectives: [],
        ),
      ),
      ScenarioCharacter(
        id: 'npc_regular',
        name: '山本太郎',
        age: 45,
        occupation: '会社員',
        publicProfile: '常連客。事件当夜も来店していた。',
        isPlayer: false,
        privateScript: PrivateScript(
          role: '容疑者',
          relationship: '常連客',
          secrets: ['健一に多額の借金がある'],
          allowedLies: ['借金のことを知らないふりをしてよい'],
          motive: '借金返済のための保険金',
          alibi: '21:25-21:35 トイレ',
          objectives: [],
        ),
      ),
      ScenarioCharacter(
        id: 'npc_manager',
        name: '佐藤誠',
        age: 38,
        occupation: 'マネージャー',
        publicProfile: 'カフェのマネージャー。被害者の右腕。',
        isPlayer: false,
        privateScript: PrivateScript(
          role: '容疑者（犯人）',
          relationship: '被害者のマネージャー',
          secrets: [
            'リストラ通告を受けていた',
            '厨房で毒を混入した',
          ],
          allowedLies: ['リストラのことを知らないと答える'],
          motive: 'リストラと保険金',
          alibi: '21:20-21:40 レジ付近',
          objectives: [],
        ),
      ),
    ],
    clues: [
      ScenarioClue(
        id: 'clue_glove',
        title: 'ゴム手袋の痕跡',
        content: '厨房のゴミ箱に青酸カリの痕跡が残ったゴム手袋。佐藤のサイズと一致。',
        type: 'physical',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_email',
        title: 'リストラ通告メール',
        content: '健一から佐藤へのメール「来週で契約終了」。送信日時は事件前日。',
        type: 'digital',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_coffee',
        title: 'コーヒーカップ',
        content: '被害者のカップにのみ毒が検出。ポットには無毒。',
        type: 'physical',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_witness',
        title: '近隣店の証言',
        content: '21:30頃、厨房の灯りが点いたのを目撃。当時厨房にいたのは佐藤のみ。',
        type: 'testimony',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_debt',
        title: '借金書',
        content: '山本のバッグから借金返済期限の書類。健一が貸し手。',
        type: 'document',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_salary',
        title: '給与明細',
        content: '田中の給与明細に2ヶ月分の未払い。健一とのメモあり。',
        type: 'document',
        importance: 'supplementary',
      ),
      ScenarioClue(
        id: 'clue_insurance',
        title: '保険証券',
        content: '健一の生命保険。受益者是正佐藤誠。',
        type: 'document',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_cyanide',
        title: '毒物在庫',
        content: '店舗倉庫にネズミ駆除用の青酸カリ。管理担当は佐藤。',
        type: 'physical',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_cctv',
        title: '防犯カメラ',
        content: '21:28 佐藤が厨房へ。21:32 厨房から出る。他に厨房入りなし。',
        type: 'digital',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_alibi',
        title: 'トイレ使用記録',
        content: '山本が21:25-21:35にトイレ。事件時刻21:30と重なるが物理的には犯行不可。',
        type: 'document',
        importance: 'supplementary',
      ),
    ],
  );
}
