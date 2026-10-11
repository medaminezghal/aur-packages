# my-aur-packages
This a repository which will hold the packages sources: PKGBUILD, patches...

## Pacman repository

Every package added or updated on `main` is built and published to a signed pacman repository hosted on the [`repo` release](../../releases/tag/repo). The build check adds it before building, so dependencies maintained here are installed prebuilt instead of being built from source.

```ini
[aur-packages]
SigLevel = Required
Server = https://github.com/medaminezghal/aur-packages/releases/download/repo
```

The signing key is published as `aur-packages.asc` in the same release. File names of packages with an epoch use `_` instead of `:`, because GitHub renames release assets containing `:`.
