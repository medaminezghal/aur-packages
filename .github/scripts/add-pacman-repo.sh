#!/usr/bin/env bash
# Add the pacman repository hosted on this repo's GitHub release to
# /etc/pacman.conf, so prebuilt packages are used instead of building them.
# Must run as root, before the build chroot is created.
#
# Env: REPO_NAME, RELEASE_TAG, GITHUB_REPOSITORY
set -euo pipefail

: "${REPO_NAME:?}" "${RELEASE_TAG:?}" "${GITHUB_REPOSITORY:?}"

url="https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG"

if ! curl -fsSL -o /dev/null "$url/$REPO_NAME.db"; then
  echo "Repository $REPO_NAME is not published yet, skipping."
  exit 0
fi

key=$(mktemp)
curl -fsSL -o "$key" "$url/$REPO_NAME.asc"
fingerprint=$(gpg --batch --with-colons --import-options show-only --import "$key" \
  | awk -F: '$1 == "fpr" { print $10; exit }')
[[ -n "$fingerprint" ]] || { echo "::error::Could not read the repository signing key"; exit 1; }

pacman-key --add "$key"
pacman-key --lsign-key "$fingerprint"

printf '\n[%s]\nSigLevel = Required\nServer = %s\n' "$REPO_NAME" "$url" >> /etc/pacman.conf
pacman -Sy --noconfirm

echo "Added repository $REPO_NAME ($url), signed by $fingerprint"
