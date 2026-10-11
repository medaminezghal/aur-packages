#!/usr/bin/env bash
# Add built packages to the pacman repository hosted on this repo's GitHub
# release, and delete the files of the versions they replace.
#
# Usage: update-pacman-repo.sh <package file>...
# Env:   REPO_NAME, RELEASE_TAG, GITHUB_REPOSITORY, GH_TOKEN,
#        GPG_KEY (fingerprint of the signing key, usable through gpg-agent)
set -euo pipefail

: "${REPO_NAME:?}" "${RELEASE_TAG:?}" "${GITHUB_REPOSITORY:?}" "${GPG_KEY:?}"
(( $# > 0 )) || { echo "::error::No package files given"; exit 1; }

db="$REPO_NAME.db.tar.zst"
files_db="$REPO_NAME.files.tar.zst"
work=$(mktemp -d)

assets() {
  gh release view "$RELEASE_TAG" -R "$GITHUB_REPOSITORY" --json assets -q '.assets[].name'
}

sign() {
  gpg --batch --yes --use-agent --detach-sign --no-armor -u "$GPG_KEY" -o "$1.sig" "$1"
}

if ! gh release view "$RELEASE_TAG" -R "$GITHUB_REPOSITORY" > /dev/null 2>&1; then
  gh release create "$RELEASE_TAG" -R "$GITHUB_REPOSITORY" \
    --title "Pacman repository" \
    --notes "Prebuilt packages used by the build checks. Managed by the publish-to-repo workflow." \
    --latest=false
fi

existing=$(assets)
for f in "$db" "$files_db"; do
  if grep -qxF "$f" <<< "$existing"; then
    gh release download "$RELEASE_TAG" -R "$GITHUB_REPOSITORY" -p "$f" -D "$work"
  fi
done

# Map each package name to the file name the repository currently holds for it.
declare -A old=()
if [[ -f "$work/$db" ]]; then
  mkdir "$work/dbx"
  bsdtar -xf "$work/$db" -C "$work/dbx"
  for desc in "$work"/dbx/*/desc; do
    name=$(sed -n '/^%NAME%$/{n;p;q}' "$desc")
    file=$(sed -n '/^%FILENAME%$/{n;p;q}' "$desc")
    old[$name]=$file
  done
fi

new_pkgs=()
to_delete=()
for pkg in "$@"; do
  info=$(bsdtar -xOf "$pkg" .PKGINFO)
  if grep -qxF 'xdata = pkgtype=debug' <<< "$info"; then
    echo "Skipping debug package $(basename "$pkg")"
    continue
  fi
  name=$(sed -n 's/^pkgname = //p' <<< "$info")

  # GitHub renames release assets with ':' (epoch), so store them with '_'.
  # repo-add records this file name, which is the name pacman downloads.
  base=$(basename "$pkg")
  file=${base//:/_}
  cp "$pkg" "$work/$file"
  sign "$work/$file"
  new_pkgs+=("$file")

  if [[ -n "${old[$name]:-}" && "${old[$name]}" != "$file" ]]; then
    to_delete+=("${old[$name]}" "${old[$name]}.sig")
  fi
done

if (( ${#new_pkgs[@]} == 0 )); then
  echo "No packages to publish."
  exit 0
fi

(cd "$work" && repo-add --sign --key "$GPG_KEY" "$db" "${new_pkgs[@]}")

# Plain copies under the names pacman requests (release assets can't be symlinks).
for f in "$REPO_NAME.db" "$REPO_NAME.files"; do
  cp --remove-destination "$work/$f.tar.zst" "$work/$f"
  cp --remove-destination "$work/$f.tar.zst.sig" "$work/$f.sig"
done
gpg --batch --armor --export "$GPG_KEY" > "$work/$REPO_NAME.asc"

upload() {
  gh release upload "$RELEASE_TAG" -R "$GITHUB_REPOSITORY" --clobber "${@/#/$work/}"
  local now
  now=$(assets)
  for f in "$@"; do
    grep -qxF "$f" <<< "$now" || { echo "::error::Asset $f is missing after upload (renamed by GitHub?)"; exit 1; }
  done
}

# Packages first, then the database, so the database never points to missing files.
pkg_assets=()
for f in "${new_pkgs[@]}"; do
  pkg_assets+=("$f" "$f.sig")
done
upload "${pkg_assets[@]}"
upload "$REPO_NAME.db" "$REPO_NAME.db.sig" "$db" "$db.sig" \
       "$REPO_NAME.files" "$REPO_NAME.files.sig" "$files_db" "$files_db.sig" \
       "$REPO_NAME.asc"

now=$(assets)
for f in "${to_delete[@]}"; do
  if grep -qxF "$f" <<< "$now"; then
    gh release delete-asset "$RELEASE_TAG" "$f" -R "$GITHUB_REPOSITORY" -y
    echo "Deleted old asset $f"
  fi
done

printf 'Published: %s\n' "${new_pkgs[@]}"
