#!/usr/bin/env bash
# kiro-kit installer — kiro-cli に memory / steering / skills / hooks を導入する
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.kiro"
FORCE=0
DRY=0
WORK_LOG_DIR=""
PATCH_AGENTS=()
AGENT_NAME="kit"
NO_AGENT=0
SET_DEFAULT=0

usage() {
  cat <<'USAGE'
kiro-kit installer

  ./install.sh [options]

既定で ~/.kiro/agents/kit.json という agent を作る。hooks は agent 設定にしか
書けないため、これがないと起動時の状態注入と記憶依頼の検知が有効にならない。

options:
  --work-log-dir DIR    作業ログの置き場所(省略可。指定するとセッション開始時に直近5件が出る)
  --agent-name NAME     作る agent の名前(既定: kit)
  --set-default         作った agent を kiro-cli の既定 agent にする
  --no-agent            agent を作らない(既存の agent に入れたいときは --patch-agent を使う)
  --patch-agent NAME    既存の ~/.kiro/agents/NAME.json に hooks と記憶KBを注入する(複数可)
  --force               既存の skill / steering ファイルを上書きする
  --dry-run             何をするかだけ表示する
  -h, --help            このヘルプ

例:
  ./install.sh                                   # 全部入り。kit agent を作る
  ./install.sh --set-default                     # さらに既定 agent にする
  ./install.sh --no-agent --patch-agent my-agent # 既存の agent に組み込む
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-log-dir) WORK_LOG_DIR="${2:?path required}"; shift 2 ;;
    --agent-name)   AGENT_NAME="${2:?name required}"; shift 2 ;;
    --set-default)  SET_DEFAULT=1; shift ;;
    --no-agent)     NO_AGENT=1; shift ;;
    --patch-agent)  PATCH_AGENTS+=("${2:?name required}"); shift 2 ;;
    --force)        FORCE=1; shift ;;
    --dry-run)      DRY=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
run()  { if [[ $DRY -eq 1 ]]; then printf '  [dry] %s\n' "$*"; else eval "$@"; fi; }

command -v kiro-cli >/dev/null 2>&1 || echo "warning: kiro-cli が PATH にありません(インストールは続行します)"

echo "==> ディレクトリを作成"
for d in bin memory skills steering agents; do
  run "mkdir -p '$DEST/$d'"
  say "$DEST/$d"
done

echo "==> スクリプトを配置"
for f in kiro-memory hook-session-start hook-remember-nudge; do
  run "install -m 0755 '$SRC/bin/$f' '$DEST/bin/$f'"
  say "bin/$f"
done

echo "==> 設定ファイル"
if [[ -f "$DEST/kit.env" ]]; then
  say "kit.env は既にあるので触りません"
else
  run "sed 's|^KIRO_WORK_LOG_DIR=.*|KIRO_WORK_LOG_DIR=\"$WORK_LOG_DIR\"|' '$SRC/kit.env.example' > '$DEST/kit.env'"
  say "kit.env を作成 (KIRO_WORK_LOG_DIR=\"$WORK_LOG_DIR\")"
fi

echo "==> skills を配置"
# 作業ログのパスは skill 本文に埋め込む(Markdown なので変数展開できないため)
LOG_LABEL="${WORK_LOG_DIR:-~/work_logs}"
for d in "$SRC"/skills/*/; do
  name="$(basename "$d")"
  target="$DEST/skills/$name/SKILL.md"
  if [[ -f "$target" && $FORCE -eq 0 ]]; then
    say "skip (既存): skills/$name  — 上書きするなら --force"
    continue
  fi
  run "mkdir -p '$DEST/skills/$name'"
  run "sed 's|@@WORK_LOG_DIR@@|$LOG_LABEL|g' '$d/SKILL.md' > '$target'"
  say "skills/$name"
done

echo "==> steering を配置"
target="$DEST/steering/01-memory-policy.md"
if [[ -f "$target" && $FORCE -eq 0 ]]; then
  say "skip (既存): steering/01-memory-policy.md — 上書きするなら --force"
else
  run "cp '$SRC/steering/01-memory-policy.md' '$target'"
  say "steering/01-memory-policy.md"
fi
if [[ ! -f "$DEST/steering/10-team-rules.md" ]]; then
  run "cp '$SRC/steering/10-team-rules.md.example' '$DEST/steering/10-team-rules.md.example'"
  say "steering/10-team-rules.md.example (.example を外すと有効になります)"
fi

echo "==> 記憶の索引を生成"
run "'$DEST/bin/kiro-memory' index >/dev/null"
say "steering/00-memory-index.md"

if [[ $NO_AGENT -eq 0 ]]; then
  echo "==> agent を作成"
  say "hooks は agent 設定にしか書けないので、これがないと起動時の状態注入が効きません"
  agent_file="$DEST/agents/$AGENT_NAME.json"
  if [[ -f "$agent_file" && $FORCE -eq 0 ]]; then
    say "skip (既存): agents/$AGENT_NAME.json"
    say "  既存の中身を活かして hooks だけ入れるなら: --patch-agent $AGENT_NAME"
  else
    run "sed -e 's|__HOME__|$HOME|g' -e 's|\"name\": \"kit\"|\"name\": \"$AGENT_NAME\"|' '$SRC/agents/kit.json' > '$agent_file'"
    say "agents/$AGENT_NAME.json"
  fi
  if [[ $SET_DEFAULT -eq 1 ]]; then
    run "kiro-cli agent set-default '$AGENT_NAME'"
    say "既定 agent を $AGENT_NAME にしました"
  fi
fi

if [[ ${#PATCH_AGENTS[@]} -gt 0 ]]; then
  echo "==> agent に hooks と記憶KBを注入"
  # 既存 JSON をマージするのはここだけ。他の処理に python は要らない
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  python3 が見つかりません。--patch-agent は既存 agent の JSON をマージするため python3 を使います。" >&2
    echo "  agent を新規に作るだけなら python3 は不要です(--patch-agent を外して実行してください)。" >&2
    exit 1
  fi
  for name in "${PATCH_AGENTS[@]}"; do
    f="$DEST/agents/$name.json"
    if [[ ! -f "$f" ]]; then
      say "見つかりません: $f"
      continue
    fi
    if [[ $DRY -eq 1 ]]; then
      say "[dry] patch $f"
      continue
    fi
    cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
    HOME_DIR="$HOME" AGENT_FILE="$f" python3 - <<'PY'
import json, os

path = os.environ["AGENT_FILE"]
home = os.environ["HOME_DIR"]
a = json.load(open(path))

a["hooks"] = {
    "agentSpawn": [{"command": f"{home}/.kiro/bin/hook-session-start", "timeout_ms": 10000}],
    "userPromptSubmit": [{"command": f"{home}/.kiro/bin/hook-remember-nudge", "timeout_ms": 5000}],
}

res = a.get("resources", [])
if not any(isinstance(r, dict) and r.get("name") == "記憶" for r in res):
    res.append({
        "type": "knowledgeBase",
        "source": f"file://{home}/.kiro/memory",
        "name": "記憶",
        "indexType": "best",
        "include": ["**/*.md"],
        "autoUpdate": True,
    })
a["resources"] = res

base = ["fs_read", "fs_write", "grep", "glob", "code", "knowledge",
        "execute_bash", "task", "introspect", "web_fetch"]
a["allowedTools"] = list(dict.fromkeys(base + a.get("allowedTools", [])))

json.dump(a, open(path, "w"), ensure_ascii=False, indent=2)
open(path, "a").write("\n")
print(f"  patched: {os.path.basename(path)} (バックアップあり)")
PY
  done
fi

echo
echo "==> 完了"
cat <<DONE

使いはじめる:
  kiro-cli chat --agent $AGENT_NAME
DONE
if [[ $NO_AGENT -eq 0 && $SET_DEFAULT -eq 0 ]]; then
  cat <<DONE
  毎回 --agent を打ちたくなければ: kiro-cli agent set-default $AGENT_NAME
DONE
fi
cat <<'DONE'

動いているか確認する:
  kiro-cli chat --no-interactive "利用可能な skill を列挙して"

記憶を1件書いてみる:
  echo '本文' | ~/.kiro/bin/kiro-memory add my-first project '1行サマリ'
  ~/.kiro/bin/kiro-memory list

チーム共通ルールを効かせる:
  mv ~/.kiro/steering/10-team-rules.md.example ~/.kiro/steering/10-team-rules.md
DONE
