---
name: morning-check
description: 作業開始前の環境チェック。git と開発環境の状態をまとめて確認する。
---

# 作業開始前チェック

以下を順に実行して結果をまとめる。

1. `git status` — 未コミットの変更
2. `git branch --show-current` — 現在のブランチ
3. `git log --oneline -5` — 直近のコミット

<!-- 各自の環境に合わせて追記する。例:
4. `docker compose ps` — DBコンテナの起動状態
5. `aws sts get-caller-identity` — 認証の有効性
-->

問題があれば対処方法を提示する。
同じ問題を繰り返し踏んでいるなら `remember` skill で記憶に残す。
