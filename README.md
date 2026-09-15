# kiro-kit

kiro-cli に「セッションをまたいで覚えている」「毎回同じ指示をしなくて済む」レイヤーを足すキット。

kiro-cli には steering / skills / hooks の下地が入っているが、既定では**全部空**なので何も起きない。
このキットはその空き枠を埋めたうえで、**永続メモリを足す**。

永続メモリは kiro-cli の純正機能ではない
（[Feature Request #6988](https://github.com/kirodotdev/Kiro/issues/6988) として要望が出ている段階）。
近いものに実験的機能の knowledge base があるが、あれは**検索して初めて出てくる**ストアで、
黙っていても効く記憶ではない。

| | 純正の knowledge base | kiro-kit の memory |
|---|---|---|
| 位置づけ | 実験的機能（要有効化） | steering の上に構築 |
| 出てくるとき | 意味検索したとき | **毎回自動で入る**（索引が steering） |
| 単位 | ファイル・ディレクトリ単位 | 1ファイル1事実 |
| 引き方 | 意味検索のみ | 索引 → grep → grep → 意味検索 |

kiro-kit は knowledge base を否定しない。記憶の本文は KB にも登録して、
索引で当たらないときの最後の手段として使う。

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

このとき **`allowedTools` は変更しない**。承認の要否は各自の設定のままにする。
毎回の承認を減らしたいなら明示的に:

```bash
./install.sh --no-agent --patch-agent my-agent --relax-tools
```

`--relax-tools` は `fs_write` と `execute_bash` を自動承認に加えるので、
何を許すことになるか理解したうえで使うこと。

既存の skill / steering / agent は**上書きしない**（`--force` で上書き）。
何をするか見るだけなら `--dry-run`。agent 名を変えたいなら `--agent-name`。

## 元に戻す

```bash
./uninstall.sh              # 何が消えるか確認してから削除
./uninstall.sh --dry-run    # 確認だけ
```

**記憶（`~/.kiro/memory/`）と `kit.env` は消さない。** あなたが書いたデータなので、
入れ直せばそのまま使える。完全に消すなら `--purge`。

`--patch-agent` で書き換えた agent は、`~/.kiro/agents/*.bak.*` から戻せる。

## 更新するとき

```bash
git pull && ./install.sh --force
```

`--force` は skills / steering / agent を上書きするが、**上書き前に `.bak.<日時>` へ退避する**ので、
自分で書き足した内容は失われない。有効化済みの `10-team-rules.md` は対象外。

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
索引で見つからないときは `/recall` が段階的に探す:

1. **全件索引を grep** (`~/.kiro/memory-index-full.md`) — 索引から省略された分もここにある
2. **記憶の本文を grep** (`~/.kiro/memory/`) — サマリに出ない細部を探す
3. **KB「記憶」を意味検索** — 言葉が思いつかないとき

KB を最後にしているのは、**意味検索が万能ではない**ため。実測では
「その記憶が何についてか」は引けるが、1ファイルに複数の話題が混ざった記憶の
主題から外れた内容は引けなかった。grep は言い換えに弱い代わりに取りこぼさないので、
言葉が分かっているうちは grep の方が確実。

### 記憶が増えてきたら

放っておくと重複した記憶が溜まり、サマリが長くなって索引を圧迫する。
棚卸しの材料は機械的に出せる:

```bash
~/.kiro/bin/kiro-memory doctor        # 重複候補・古い記憶・長すぎるサマリ
~/.kiro/bin/kiro-memory doctor --stale-days 90 --desc-max 60
```

doctor が出すのは**候補であって判断ではない**。重複候補に挙がったペアが
同じアプリの別課題だった、ということは普通に起きる。`memory-gc` 側で本文を
読んで精査する前提になっている。

記憶が 50 件を超えると、セッション開始時に棚卸しを促すようになる
（閾値は `KIRO_MEMORY_GC_THRESHOLD` で変更可能）。
実際の統合・更新・短縮は `memory-gc` skill が担当する。

### 索引が長くなってきたら

索引に載せる件数に上限をかけられる（既定は無制限）:

```bash
export KIRO_MEMORY_INDEX_MAX=40    # project/reference は新しい順に40件まで
```

- **`feedback` と `user` は上限の対象外** — 件数が少なく、あなたの好みや役割という
  落としてはいけない情報なので常に全件載せる
- 省略された分は索引に「...他 N 件(古い順に省略)」と明記される
- **全件は `~/.kiro/memory-index-full.md` に常に書き出される**（steering ではないので
  コンテキストには入らない）。`recall` skill はここを grep して探す

古い記憶ほど落ちる方式なので、**長く変わらない重要な事実**（環境の落とし穴など）が
省略されることがある。それでも grep で確実に引けるようにフル索引を用意している。

**`memory-gc` は勝手に消さない。** 削除と統合は必ず確認を取ってから実行する。
記憶が消えたことに気づくのは、それが必要になった瞬間だから。

実際に 11 件の記憶で走らせたときは、重複候補に挙がったペアを「同じアプリの別課題」と
判断して統合せず、短縮候補も大半を「検索の手がかりが残っているので現状維持が妥当」と
却下したうえで、1件だけ提案して承認待ちで停止した。記憶は1バイトも変更されなかった。

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
├── skills/<name>/SKILL.md     remember / recall / memory-gc / start-work / save-log / morning-check
├── bin/
│   ├── kiro-memory            記憶の追加・削除・索引生成
│   ├── hook-session-start     agentSpawn: git状態と直近ログを注入
│   └── hook-remember-nudge    userPromptSubmit: 記憶の依頼を検知して手順を注入
├── agents/kit.json            hooks と記憶KBを有効にした agent（CLI 用）
├── hooks/kiro-kit.json        同じ hooks の Kiro IDE 用（CLI では無視される）
└── kit.env                    環境依存の設定（作業ログの場所など）
```

## 安全側の作り

配布物として他人の環境で動くので、入力がそのままパスになる箇所は検証している。

- **slug と agent 名はパス区切りを弾く。** 英数字・ハイフン・アンダースコア・ドットのみ。
  `../` を含む slug で `~/.kiro/memory/` の外にファイルを書いたり消したりできない。
  記憶はモデルが自動で書くので、会話の内容がそのまま slug になりうるため。
- **`--force` は上書き前に `.bak.<日時>` へ退避する。**
- **`--patch-agent` は `allowedTools` を変更しない。** 承認の要否は各自の設定のまま
  （`--relax-tools` を明示したときだけ広げる）。
- **`memory-gc` は記憶を勝手に消さない。** 削除と統合は承認を取ってから。
- **`uninstall.sh` は記憶と `kit.env` を残す。** 全部消すなら `--purge`。

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

### steering の inclusion は always のままにする

IDE は `inclusion` の全モード（`always` / `fileMatch` / `manual` / `auto`）に対応しているが、
**CLI は `always` しか読まない。それ以外は条件つきで入るのではなく、丸ごと除外される。**

| inclusion | IDE | CLI |
|---|---|---|
| `always` | 常に入る | 常に入る |
| `fileMatch` / `manual` / `auto` | 条件つきで入る | **一切入らない** |

配布する steering を `fileMatch` にすると、CLI で使っている人にはそのルールが
完全に消える。**チームで共有するファイルは `always` のままにすること。**
出し分けたいなら、IDE 専用と割り切った別ファイルとして各自のワークスペース
（`.kiro/steering/`）に置く。

## 期待値について

steering と hooks は確実に効く。一方 **memory は書かないと貯まらない**。
フックと steering で書くよう仕向けてはいるが、モデルが「これは記憶すべきだ」と
判断するかは毎回の運次第なので、最初のうちは詰まったときに
「今のを覚えといて」と明示的に言った方が確実に貯まる。10件ほど貯まると効きが変わる。

## 触っていない領域

kiro-cli には他に `subagent`（DAGで並列実行）、`/plan`、`task`、`powers` がある。
これらは「毎回効く土台」ではなく「使うと強い道具」なので、このキットには含めていない。
