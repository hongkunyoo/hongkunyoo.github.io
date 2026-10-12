#!/bin/bash
# 포스트 대표 이미지(front matter의 image:)의 WebP 변환본을 생성합니다.
#   <name>.webp      : 최대 1200px 폭 (포스트 상단 이미지)
#   <name>-600.webp  : 600px 폭 (목록 카드 썸네일)
# 원본은 og:image 용도로 그대로 둡니다. 필요: cwebp (brew install webp)
set -euo pipefail
cd "$(dirname "$0")/.."
{ for f in _posts/*; do awk 'NR==1{next} /^---/{exit} /^image:/{print $2}' "$f"; done; grep -E '^[[:space:]]+image:' _config.yml | awk '{print $2}'; } | tr -d '\r' | sort -u | while read -r img; do
  src=".${img}"
  [ -f "$src" ] || { echo "skip (missing): $src"; continue; }
  base="${src%.*}"
  # 원본보다 크게 늘리지 않도록 폭 확인 (macOS sips 사용, 없으면 항상 리사이즈)
  width=$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/{print $2}')
  width=${width:-9999}
  for pair in "1200:80:${base}.webp" "600:75:${base}-600.webp"; do
    IFS=: read -r w q out <<< "$pair"
    [ -f "$out" ] && [ "$out" -nt "$src" ] && continue
    resize=(); [ "$width" -gt "$w" ] && resize=(-resize "$w" 0)
    cwebp -quiet -q "$q" ${resize[@]+"${resize[@]}"} "$src" -o "$out" && echo "made $out"
  done
done
