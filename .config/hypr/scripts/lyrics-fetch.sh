#!/usr/bin/env bash
# Prints synced LRC lyrics for a track (or nothing), from a local cache or
# LRCLIB. Usage: lyrics-fetch.sh <title> <artist> <album> <duration-seconds>
#
# Exact metadata lookup first (title+artist+album+duration), then a fuzzy
# search picking the closest duration. Results are cached per track so
# repeats and offline playback are instant; misses are cached too, but only
# for a day, in case the track gets lyrics later.
set -uo pipefail

title="${1:-}"
artist="${2:-}"
album="${3:-}"
duration="${4:-0}"

[ -z "$title" ] && exit 0

cache_dir="$HOME/.cache/dynamic-glacier/lyrics"
mkdir -p "$cache_dir"
key=$(printf '%s\n%s\n%s\n%s' "$artist" "$title" "$album" "$duration" | sha1sum | cut -d' ' -f1)
cache_file="$cache_dir/$key.lrc"

if [ -f "$cache_file" ]; then
    if [ -s "$cache_file" ] || [ -z "$(find "$cache_file" -mmin +1440 2>/dev/null)" ]; then
        cat "$cache_file"
        exit 0
    fi
fi

ua="dynamic-glacier/1.0 (https://github.com/Legfena/QS-DFMID26)"
enc() { jq -rn --arg v "$1" '$v|@uri'; }

lyrics=""
duration_int=${duration%.*}

if [ "$duration_int" -gt 0 ] 2>/dev/null; then
    lyrics=$(curl -s --max-time 8 -H "User-Agent: $ua" \
        "https://lrclib.net/api/get?track_name=$(enc "$title")&artist_name=$(enc "$artist")&album_name=$(enc "$album")&duration=$duration_int" \
        | jq -r '.syncedLyrics // empty' 2>/dev/null)
fi

if [ -z "$lyrics" ]; then
    lyrics=$(curl -s --max-time 8 -H "User-Agent: $ua" \
        "https://lrclib.net/api/search?track_name=$(enc "$title")&artist_name=$(enc "$artist")" \
        | jq -r --argjson d "${duration_int:-0}" '
            [ .[] | select(.syncedLyrics != null and .syncedLyrics != "") ]
            | if $d > 0 then sort_by((.duration - $d) | fabs) else . end
            | .[0].syncedLyrics // empty' 2>/dev/null)
fi

printf '%s' "$lyrics" > "$cache_file"
printf '%s' "$lyrics"
