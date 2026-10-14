#!/usr/bin/env bash
# Cloudflare Pages: genera dist/ con los archivos web de scripts/pages-manifest.txt
# y nada más. Se detiene si una ruta no es válida, no está en git o falta,
# y si dist/ no coincide exactamente con el manifiesto.
set -euo pipefail

cd "$(dirname "$0")/.."
manifest="scripts/pages-manifest.txt"
out="dist"

rm -rf "$out"
mkdir "$out"

count=0
while IFS= read -r path || [ -n "$path" ]; do
  case "$path" in ''|'#'*) continue ;; esac
  case "$path" in
    /*|*..*|.*|*/.*|supabase/*) echo "Ruta no permitida en el manifiesto: $path" >&2; exit 1 ;;
  esac
  case "$path" in
    *.html|*.js|*.css|*.jpg) ;;
    *) echo "Tipo de archivo no permitido en el manifiesto: $path" >&2; exit 1 ;;
  esac
  if ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
    echo "El archivo no está en git: $path" >&2; exit 1
  fi
  if [ ! -f "$path" ]; then
    echo "Falta el archivo: $path" >&2; exit 1
  fi
  mkdir -p "$out/$(dirname "$path")"
  cp "$path" "$out/$path"
  count=$((count + 1))
done < "$manifest"

published=$(find "$out" -type f | wc -l | tr -d ' ')
if [ "$published" -ne "$count" ]; then
  echo "dist/ tiene $published archivos y el manifiesto $count" >&2; exit 1
fi
if find "$out" \( -name '.*' -o -name '*.md' -o -name '*.sql' -o -path "$out/supabase" -o -path "$out/supabase/*" \) | grep -q .; then
  echo "dist/ contiene archivos que no deben publicarse" >&2; exit 1
fi

echo "Pages: $published archivos publicados"
