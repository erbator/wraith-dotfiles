#!/usr/bin/env bash
# Thumbnail cache for the island's wallpaper picker.
#
#   wall-thumbs.sh <wallpaper dir> <cache dir>
#
# Each image gets <cache>/<md5 of its full path>.jpg (the same name the panel
# computes with Qt.md5), 480px wide. Only missing ones are made, in parallel;
# progress goes to stdout as "done/total" lines. Thumbs of deleted images are
# pruned.
set -u

dir="${1:?wallpaper dir}"
cache="${2:?cache dir}"
mkdir -p "$cache"

mapfile -d '' files < <(find "$dir" -mindepth 1 -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' \) -print0)

declare -A keep=()
todo=()
for f in "${files[@]}"; do
    sum=$(printf '%s' "$f" | md5sum | cut -d' ' -f1)
    keep["$sum.jpg"]=1
    [[ -s "$cache/$sum.jpg" ]] || todo+=("$f"$'\t'"$cache/$sum.jpg")
done

# Prune thumbs whose image is gone.
for t in "$cache"/*.jpg; do
    [[ -e "$t" ]] || continue
    [[ -n "${keep[$(basename "$t")]:-}" ]] || rm -f -- "$t"
done

total=${#todo[@]}
echo "0/$total"
[[ $total -eq 0 ]] && exit 0

make_one() {
    src="${1%%$'\t'*}"
    out="${1#*$'\t'}"
    if command -v vipsthumbnail >/dev/null; then
        vipsthumbnail "$src" -s 480x -o "$out[Q=82,strip]" 2>/dev/null
    else
        magick "$src[0]" -thumbnail 480x -quality 82 "$out" 2>/dev/null
    fi
    echo x
}
export -f make_one

printf '%s\0' "${todo[@]}" |
    xargs -0 -P "$(nproc)" -I{} bash -c 'make_one "$1"' _ {} |
    awk -v total="$total" '{ n++; if (n % 10 == 0 || n == total) { print n "/" total; fflush() } }'
