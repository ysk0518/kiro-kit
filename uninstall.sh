#!/usr/bin/env bash
# kiro-kit uninstaller — 入れたものを剥がす。記憶(~/.kiro/memory)は消さない
set -euo pipefail

DEST="$HOME/.kiro"
YES=0
DRY=0
PURGE=0
AGENT_NAME="kit"

usage() {
  cat <<'USAGE'
kiro-kit uninstaller

  ./uninstall.sh [options]

kiro-kit が置いたファイルを削除する。
**記憶(~/.kiro/memory/)と kit.env は既定で残す** — あなたが書いたデータなので。

options:
  --agent-name NAME  削除する agent の名前(既定: kit)
  --purge            記憶と kit.env も消す(元に戻せません)
  --dry-run          何を消すかだけ表示する
  -y, --yes          確認せずに実行する
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-name) AGENT_NAME="${2:?name required}"; shift 2 ;;
    --purge)      PURGE=1; shift ;;
    --dry-run)    DRY=1; shift ;;
    -y|--yes)     YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

TARGETS=(
  "$DEST/bin/kiro-memory"
  "$DEST/bin/hook-session-start"
  "$DEST/bin/hook-remember-nudge"
  "$DEST/steering/00-memory-index.md"
  "$DEST/steering/01-memory-policy.md"
  "$DEST/steering/10-team-rules.md.example"
  "$DEST/hooks/kiro-kit.json"
  "$DEST/agents/$AGENT_NAME.json"
)
for s in remember recall start-work save-log morning-check; do
  TARGETS+=("$DEST/skills/$s")
done
[[ $PURGE -eq 1 ]] && TARGETS+=("$DEST/memory" "$DEST/kit.env")

echo "==> 削除するもの"
found=0
for t in "${TARGETS[@]}"; do
  if [[ -e "$t" ]]; then printf '  %s\n' "${t/#$HOME/~}"; found=1; fi
done
[[ $found -eq 1 ]] || { echo "  (kiro-kit のファイルは見つかりませんでした)"; exit 0; }

echo
echo "==> 残すもの"
if [[ $PURGE -eq 0 ]]; then
  [[ -d "$DEST/memory" ]] && printf '  ~/.kiro/memory/ (%s件の記憶)\n' "$(ls "$DEST/memory"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  [[ -f "$DEST/kit.env" ]] && echo "  ~/.kiro/kit.env"
else
  echo "  (なし — --purge が指定されています)"
fi
[[ -f "$DEST/steering/10-team-rules.md" ]] && echo "  ~/.kiro/steering/10-team-rules.md (あなたが有効化したもの)"
echo "  ~/.kiro/agents/*.json (kit 以外。--patch-agent で入れた hooks は手で消してください)"

if [[ $DRY -eq 1 ]]; then echo; echo "(dry-run のため何もしていません)"; exit 0; fi

if [[ $YES -eq 0 ]]; then
  echo
  read -r -p "削除しますか? [y/N] " ans
  case "$ans" in [yY]*) ;; *) echo "中止しました"; exit 0 ;; esac
fi

for t in "${TARGETS[@]}"; do rm -rf "$t"; done
# 空になったディレクトリだけ片付ける
for d in bin skills steering hooks agents memory; do rmdir "$DEST/$d" 2>/dev/null || true; done

echo
echo "==> 完了"
if [[ $PURGE -eq 0 && -d "$DEST/memory" ]]; then
  echo "記憶は ~/.kiro/memory/ に残っています。入れ直せばそのまま使えます。"
  echo "完全に消すなら: ./uninstall.sh --purge"
fi
echo "--patch-agent で既存 agent に入れた hooks は、その agent の .bak から戻せます:"
echo "  ls ~/.kiro/agents/*.bak.*"
