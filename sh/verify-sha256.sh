#!/bin/bash
#=================================================
# Проверка SHA-256 скачанного ассета GitHub-релиза
#
# Использование:
#   verify-sha256.sh <файл> <owner/repo> <тег> <имя-ассета> [url-файла-сумм]
#
# Эталонная сумма берётся:
#   1. из поля digest ассета в GitHub API (релизы, опубликованные после
#      середины 2025 года; GITHUB_TOKEN из env снимает лимит API);
#   2. иначе из файла сумм релиза (checksums.txt и т.п.), если передан URL.
#
# Код возврата:
#   0 — сумма совпала ИЛИ эталона нет (печатается ::warning, файл не проверен)
#   1 — сумма НЕ совпала: файл использовать нельзя
#=================================================

FILE="$1"
REPO="$2"
TAG="$3"
ASSET="$4"
SUMS_URL="$5"

if [ ! -f "$FILE" ]; then
    echo "::warning title=Проверка SHA-256::Файл $FILE не найден"
    exit 1
fi

EXPECTED=""
SOURCE=""

# 1. digest из GitHub API
AUTH=()
[ -n "$GITHUB_TOKEN" ] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
EXPECTED=$(curl -fsSL --max-time 20 "${AUTH[@]}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO}/releases/tags/${TAG}" 2>/dev/null \
    | jq -r --arg n "$ASSET" '.assets[]? | select(.name == $n) | .digest // empty' 2>/dev/null \
    | sed -n 's/^sha256://p' | head -n1)
[ -n "$EXPECTED" ] && SOURCE="GitHub API digest"

# 2. Файл сумм релиза. Строки вида «<sha256>  ./<имя>» или «<sha256>  <имя>».
if [ -z "$EXPECTED" ] && [ -n "$SUMS_URL" ]; then
    EXPECTED=$(curl -fsSL --max-time 20 "$SUMS_URL" 2>/dev/null \
        | awk -v n="$ASSET" '{f=$2; sub(/^\*/, "", f); sub(/^\.\//, "", f)} f == n {print $1; exit}')
    [ -n "$EXPECTED" ] && SOURCE="$(basename "$SUMS_URL")"
fi

ACTUAL=$(sha256sum "$FILE" | awk '{print $1}')

if [ -z "$EXPECTED" ]; then
    echo "::warning title=SHA-256 не проверена::${REPO} ${TAG} ${ASSET}: эталонная сумма недоступна, файл не проверен (sha256 ${ACTUAL})"
    exit 0
fi

EXPECTED=$(printf '%s' "$EXPECTED" | tr 'A-F' 'a-f')
if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "::warning title=SHA-256 НЕ СОВПАЛА::${REPO} ${TAG} ${ASSET}: ожидалась ${EXPECTED} (${SOURCE}), получена ${ACTUAL}"
    exit 1
fi

echo ">>> SHA-256 OK (${SOURCE}): ${ACTUAL}"
exit 0
