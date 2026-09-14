# kiro-kit

kiro-cli に「セッションをまたいで覚えている」「毎回同じ指示をしなくて済む」レイヤーを足すキット。

kiro-cli には steering / skills / hooks / memory の下地が最初から入っているが、
既定では**全部空**なので何も起きない。このキットはその空き枠を埋める。

## これを入れると変わること

| 前 | 後 |
|---|---|
| 「課題管理ツールとGitHubを取り違えないで」を毎回言う | steering に書けば毎セッション自動で効く |
| 前回何をしていたか毎回説明する | 起動時にブランチ・変更・直近の作業ログが自動で入る |
| 環境の落とし穴を毎回踏み直す | 一度記録すれば次回のセッションが最初から知っている |
| 手順を毎回プロンプトで書く | skill として呼べる |

## 前提

- kiro-cli 2.21 以降

外部依存はない。bash だけで動く。
（既存 agent に注入する `--patch-agent` を使うときだけ、JSON の編集に python3 を呼ぶ）

## 入れかた

```bash
git clone <このリポジトリ> && cd kiro-kit
./install.sh
kiro-cli chat --agent kit
```

これで全部入る。`kit` という agent が作られるのは、**hooks が agent 設定にしか
書けない**ため（グローバルな置き場所がない）。毎回 `--agent` を打ちたくなければ:

```bash
kiro-cli agent set-default kit          # または ./install.sh --set-default
```

作業ログを使っているなら、その場所を教えると起動時に直近5件が自動で入る:

```bash
./install.sh --work-log-dir ~/workspace/work_logs
```

**既に自分の agent を持っている場合**は、新しく作らずそこに組み込める:

```bash
./install.sh --no-agent --patch-agent my-agent   # hooks と記憶KBを注入（バックアップあり）
```

既存の skill / steering / agent は**上書きしない**（`--force` で上書き）。
何をするか見るだけなら `--dry-run`。agent 名を変えたいなら `--agent-name`。

## 使いかた

### 記憶する

```bash
cat <<'BODY' | ~/.kiro/bin/kiro-memory add test-parallel-fail project 'ローカルでだけ落ちるテストは、まず並列実行を疑う'
CI では通るのにローカルで落ちるテストがある。原因はテストコードではなく実行の仕方だった。

**なぜ:** 複数のテストが同じテスト用DBを共有していて、片方の後始末が
もう片方の実行中に走るため。テストコードを読んでも分からない。
**どう使うか:** ローカルでだけ落ちるテストを見たら、原因調査に入る前に直列実行を試す。
BODY
```

書くべきなのは**コードを読んでも分からないこと**。「なぜその選択をしたか」「何を踏んだか」であって、
関数名や構造ではない。それらは読めば分かるので記憶する価値がない。

チャット中に「これ覚えといて」と言えば、フックが手順と既存一覧を注入するので、そのまま書かれる。

```bash
~/.kiro/bin/kiro-memory list        # 一覧
~/.kiro/bin/kiro-memory show <slug> # 本文
~/.kiro/bin/kiro-memory rm <slug>   # 削除（索引も自動更新）
```

### 思い出す

索引は毎セッション自動で入るので、基本は何もしなくてよい。
本文が要るときは `/recall` を呼ぶか、KB「記憶」を意味検索する。

### チーム共通ルールを効かせる

```bash
mv ~/.kiro/steering/10-team-rules.md.example ~/.kiro/steering/10-team-rules.md
```

ここに書いたことは全員の全セッションに入る。
**毎回言っているのに毎回守られないこと**だけを書く。たまにしか要らないことを書くと
コンテキストを食うだけなので書かない。

## 何がどこに置かれるか

```
~/.kiro/
├── steering/                  毎セッション自動でコンテキストに入る
│   ├── 00-memory-index.md     記憶の索引（自動生成・手編集しない）
│   ├── 01-memory-policy.md    何を・いつ・どう記憶するかのルール
│   └── 10-team-rules.md       チーム共通ルール（.example を外すと有効）
├── memory/<slug>.md           1ファイル1事実の永続メモリ
├── skills/<name>/SKILL.md     remember / recall / start-work / save-log / morning-check
├── bin/
│   ├── kiro-memory            記憶の追加・削除・索引生成
│   ├── hook-session-start     agentSpawn: git状態と直近ログを注入
│   └── hook-remember-nudge    userPromptSubmit: 記憶の依頼を検知して手順を注入
├── agents/kit.json            hooks と記憶KBを有効にした agent（CLI 用）
├── hooks/kiro-kit.json        同じ hooks の Kiro IDE 用（CLI では無視される）
└── kit.env                    環境依存の設定（作業ログの場所など）
```

## 仕組みとハマりどころ

kiro-cli の実装を調べて分かったことで、公式ドキュメントに書かれていない点:

- **steering は `inclusion: always` しか読まれない。**
  `manual` / `fileMatch` を指定したファイルは CLI 側で明示的に除外される
  (Kiro IDE とは挙動が違う)。常時効かせたいなら always にする。

- **グローバルの steering と skills は自動でロードされる。**
  agent の `resources` に書く必要はない。KB 登録が要るのは意味検索したいときだけ。

- **hooks は agent 設定 (`~/.kiro/agents/<name>.json`) にしか書けない。**
  グローバルな置き場所がないので、agent ごとに入れる必要がある
  (install.sh が `kit` agent を作るのも、`--patch-agent` があるのもこのため)。
  トリガーは `agentSpawn` / `userPromptSubmit` / `preToolUse` / `postToolUse` / `stop` の5種。

- **組み込みの `kiro_default` では hooks が効かない。**
  設定ファイルを持たない agent なので、hooks の書きようがない。
  `--agent` を付けずに起動すると、こうなる（実測）:

  | | `kiro_default` | 自前の agent |
  |---|---|---|
  | steering（記憶索引・ルール） | 効く | 効く |
  | skills | 効く | 効く |
  | hooks（起動時の状態注入・記憶依頼の検知） | **効かない** | 効く |
  | KB「記憶」の意味検索 | **使えない** | 使える |

  記憶とルールはグローバルに読まれるので `kiro_default` でも半分は動く。
  取りこぼすのは hooks と KB 検索だけなので、実害を感じないなら既定のままでも困らない。
  全部有効にするなら `kiro-cli agent set-default kit`。

- **フックが受け取る入力の形（実測）:**
  ```
  stdin: {"hook_event_name":"userPromptSubmit","cwd":"...","prompt":"..."}
  env  : USER_PROMPT, KIRO_SESSION_ID
  ```
  `USER_PROMPT` は**環境変数**であって stdin の JSON キーではない（キーは `prompt`）。
  取り違えるとフックは「成功」扱いのまま何も出力しないので気づきにくい。
  標準出力がそのままモデルに渡り、exit 0 が正常。

## Kiro IDE で使う

`~/.kiro/` 配下はグローバル設定として **IDE も読む**ので、install.sh を実行した環境で
Kiro IDE を開けば記憶もルールも skills もそのまま引き継がれる。CLI と IDE で同じ記憶を共有できる。

| | CLI | IDE |
|---|---|---|
| steering（記憶索引・ルール） | 効く | 効く |
| skills | 効く | 効く |
| agents | 効く | 効く |
| memory | 効く（`kiro-memory` はターミナルから） | 効く |
| hooks | `agents/kit.json` 内に定義 | `hooks/kiro-kit.json` を配置 |

hooks だけ形式が違うため、install.sh は両方を置く。CLI は独立した hooks ファイルを
読まないので、二重に発火することはない（実測で確認済み）。

**IDE 側の hooks は未検証。** ドキュメントの仕様どおりに書いてあるが、
手元に Kiro IDE がないため動作確認できていない。特に `PromptSubmit` が渡す
JSON のキー名が不明なので、`hook-remember-nudge` は入力全体から検知語を探す
フォールバックを持たせてある。動かない場合は
`~/.kiro/hooks/kiro-kit.json` の `trigger` 名を実際のものに直せばよい。

IDE では steering の `inclusion` が `always` 以外も機能する
（CLI は公式に非対応）。`fileMatch` と `fileMatchPattern` を使えば
「Go を触るときだけこのルール」といった出し分けができる。

## 期待値について

steering と hooks は確実に効く。一方 **memory は書かないと貯まらない**。
フックと steering で書くよう仕向けてはいるが、モデルが「これは記憶すべきだ」と
判断するかは毎回の運次第なので、最初のうちは詰まったときに
「今のを覚えといて」と明示的に言った方が確実に貯まる。10件ほど貯まると効きが変わる。

## 触っていない領域

kiro-cli には他に `subagent`（DAGで並列実行）、`/plan`、`task`、`powers` がある。
これらは「毎回効く土台」ではなく「使うと強い道具」なので、このキットには含めていない。
