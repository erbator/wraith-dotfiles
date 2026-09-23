#!/usr/bin/env bash
# Refreshes the exchange-rate cache behind the calculator's currency
# conversion. Rates come from the fawazahmed0 currency API (daily, no key,
# ~340 currencies including crypto), all relative to EUR. A no-op while the
# cache is under twelve hours old, so the calculator can call it on every
# open.
set -uo pipefail

cache="$HOME/.cache/dynamic-glacier/rates.json"
mkdir -p "$(dirname "$cache")"

if [ -s "$cache" ] && [ -z "$(find "$cache" -mmin +720 2>/dev/null)" ]; then
    exit 0
fi

tmp="$cache.tmp"

for url in \
    "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.min.json" \
    "https://latest.currency-api.pages.dev/v1/currencies/eur.min.json"; do
    if curl -s --max-time 10 "$url" -o "$tmp" && jq -e '.eur.usd' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$cache"
        exit 0
    fi
done

rm -f "$tmp"
exit 1
