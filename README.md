# my-aur-packages
This a repository which will hold the packages sources: PKGBUILD, patches...

## Pacman repository

Every package added or updated on `main` is built and published to a signed pacman repository hosted on the [`repo` release](../../releases/tag/repo). The build check adds it before building, so dependencies maintained here are installed prebuilt instead of being built from source.

```ini
[aur-packages]
SigLevel = Required
Server = https://github.com/medaminezghal/aur-packages/releases/download/repo
```

Before syncing, import and locally sign the signing key (published as `aur-packages.asc` in the same release), otherwise pacman rejects the database with "unknown trust":

```sh
curl -fsSLO https://github.com/medaminezghal/aur-packages/releases/download/repo/aur-packages.asc
sudo pacman-key --add aur-packages.asc
sudo pacman-key --lsign-key 2EECE5156D8DE0C50636E37621707FBE029E96B5
```

File names of packages with an epoch use `_` instead of `:`, because GitHub renames release assets containing `:`.
