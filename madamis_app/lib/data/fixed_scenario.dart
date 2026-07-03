import '../models/scenario.dart';

/// MVP用固定シナリオ: 洋館の殺人事件（4人）
Scenario createFixedScenario({int playerCount = 4}) {
  return Scenario(
    id: 'fixed_mansion_001',
    title: '霧の洋館に消えた令嬢',
    genre: '洋館',
    playerCount: playerCount,
    synopsis: '''
1924年、イギリス郊外の洋館「ブラックウッド邸」。
富豪の令嬢エミリー・ブラックウッドの誕生日パーティーが開かれていた。
午後10時、雷鳴と共に停電が起き、15分後にエミリーの部屋で
彼女が毒入りのワイングラスと共に倒れているのが発見された。

扉は内側から施錠されており、窓も開いていない。
この館にいた4人だけが容疑者だ。
犯人は誰か？そして、なぜエミリーを殺したのか？
''',
    epilogue: '''
事件から1週間後、真実は明らかになった。
エミリーは遺言書の更改を予告しており、相続問題が動機となった。
しかし、本当の悲劇は、誰もが秘密を抱えていたことだった。
''',
    truth: ScenarioTruth(
      culpritId: 'char_butler',
      crimeDescription: 'エミリー・ブラックウッドを毒殺',
      method: 'ワインに青酸カリを混入。停電中の混乱に乗じて配膳',
      motive: 'エミリーの遺言書更改により、長年の忠勤が報われないと知ったため',
      timeOfCrime: '22:15',
      location: 'エミリーの私室（2階東）',
      explanation: '''
執事のHarrisonは、エミリーが遺言書を更改し、執事への遺産が
ゼロになることを知っていた。停電の15分間、配膳を担当した
Harrisonはワインに毒を混入。鍵の管理権限を使い、後から
施錠したふりをしたのは、エミリー自身が施錠していたため
（彼女は毒を飲む前に施錠していた）。

決定的な手がかり:
- 配膳トレイの青酸カリの痕跡
- Harrisonの遺言書更改通知
- 停電中の配膳記録
''',
    ),
    characters: [
      ScenarioCharacter(
        id: 'char_doctor',
        name: 'Dr. James Whitmore',
        age: 45,
        occupation: '家庭医',
        publicProfile: 'ブラックウッド家の主治医。冷静で知的な印象。',
        isPlayer: true,
        privateScript: PrivateScript(
          role: '容疑者・家庭医',
          relationship: 'エミリーの主治医。彼女の健康状態を把握している。',
          secrets: [
            'エミリーは余命6ヶ月と診断していたが、本人には告げていない',
            'エミリーから「もし私に何かあったら、この手紙を」と託された',
          ],
          allowedLies: ['エミリーの健康状態について「良好」と答えてよい'],
          motive: 'エミリーの死により、診療報酬の継続が途絶える',
          alibi: '22:00-22:20 書斎で医学書を読んでいた（独り）',
          objectives: ['犯人を特定する', '託された手紙の内容を秘密にする'],
        ),
      ),
      ScenarioCharacter(
        id: 'char_niece',
        name: 'Victoria Blackwood',
        age: 28,
        occupation: '令嬢（姪）',
        publicProfile: 'エミリーの姪。相続権第2順位。華やかな服装。',
        isPlayer: true,
        privateScript: PrivateScript(
          role: '容疑者・相続人',
          relationship: 'エミリーの姪。叔母とは表面的には良好な関係。',
          secrets: [
            'エミリーから相続を全て取り消すと宣告されていた',
            '事件前、エミリーの部屋で激しい口論があった',
          ],
          allowedLies: ['口論があったことを否定してよい'],
          motive: '相続全取り消しの宣告を受けていた',
          alibi: '22:00-22:20 応接室で一人ワインを飲んでいた',
          objectives: ['相続を確保する', '口論の事実を隠す'],
        ),
      ),
      ScenarioCharacter(
        id: 'char_lawyer',
        name: 'Richard Ashford',
        age: 52,
        occupation: '弁護士',
        publicProfile: 'ブラックウッド家の顧問弁護士。遺言書の管理を担当。',
        isPlayer: true,
        privateScript: PrivateScript(
          role: '容疑者・弁護士',
          relationship: 'エミリーの法律顧問。遺言書更改の準備中。',
          secrets: [
            '新遺言書の草稿を持っている（執事への遺産削除が記載）',
            'エミリーから「明日正式に更改する」と告げられていた',
          ],
          allowedLies: ['遺言書更改の内容について「詳しくは知らない」と答えてよい'],
          motive: 'エミリー死亡により、遺言書更改が中止され旧遺言書が有効に',
          alibi: '22:00-22:20 事務室で書類整理（独り）',
          objectives: ['旧遺言書の有効性を維持する', '新遺言書の存在を隠す'],
        ),
      ),
      ScenarioCharacter(
        id: 'char_butler',
        name: 'Harrison',
        age: 58,
        occupation: '執事',
        publicProfile: '30年間ブラックウッド家に仕える老執事。誠実な印象。',
        isPlayer: true,
        privateScript: PrivateScript(
          role: '容疑者・執事（犯人）',
          relationship: 'エミリーの最も信頼する使用人。',
          secrets: [
            '遺言書更改で自分への遺産が全て削除されることを知っていた',
            '青酸カリを以前から厨房に隠していた（ネズミ駆除の名目）',
            '停電中にワインを配膳したのは自分だけ',
          ],
          allowedLies: [
            '遺言書更改の内容を知らないふりをする',
            '青酸カリの存在を知らないと答える',
          ],
          motive: '30年の忠勤が報われない遺言書更改への怒り',
          alibi: '22:00-22:20 配膳と停電対応で館内を移動（独り）',
          objectives: ['犯人としてバレない', '遺言書更改の事実を隠す'],
        ),
      ),
    ],
    clues: [
      ScenarioClue(
        id: 'clue_poison_tray',
        title: '配膳トレイの検査結果',
        content: '配膳トレイの縁に青酸カリの痕跡。ワイングラスを運んだ人物の指紋と一致。',
        type: 'physical',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_will_notice',
        title: '遺言書更改の通知',
        content: 'エミリーから執事Harrisonへの手紙。「明日、遺言書を更改する。あなたへの遺産は全て別の用途に充てる」。',
        type: 'document',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_serving_log',
        title: '配膳記録',
        content: '停電中（22:05-22:20）、ワインの配膳を行ったのは執事Harrisonのみ。',
        type: 'document',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_cyanide',
        title: '青酸カリの在庫',
        content: '厨房の倉庫に青酸カリが保管されていた。最近の使用記録がない。',
        type: 'physical',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_argument',
        title: '使用人の証言',
        content: '事件前、姪Victoriaがエミリーの部屋から怒声を上げて出てきたのを目撃。',
        type: 'testimony',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_medical',
        title: 'Dr. Whitmoreの診断記録',
        content: 'エミリーは余命6ヶ月。本人には告げていない。',
        type: 'document',
        importance: 'supplementary',
      ),
      ScenarioClue(
        id: 'clue_draft_will',
        title: '新遺言書の草稿',
        content: '弁護士Ashfordが所持。執事への遺産記載が削除されている。',
        type: 'document',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_lock',
        title: '鍵の状態',
        content: 'エミリーの部屋の鍵は内側から施錠。施錠はエミリー自身が行った。',
        type: 'physical',
        importance: 'supplementary',
      ),
      ScenarioClue(
        id: 'clue_wine',
        title: 'ワインボトル',
        content: 'ワインボトルに毒は混入されていない。グラスにのみ毒が検出。',
        type: 'physical',
        importance: 'important',
      ),
      ScenarioClue(
        id: 'clue_power',
        title: '停電の記録',
        content: '22:05に停電。22:18に復電。停電中は館内が完全な暗闇だった。',
        type: 'document',
        importance: 'supplementary',
      ),
    ],
  );
}
