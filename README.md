# install-update-launcher

**English** | [Français](README.fr.md)

Shared Bash library providing consistent installation and update behavior for launcher projects.

This package installs and updates only itself. Installing multiple launcher projects is the responsibility of `uni-launcher`.

## Integration

A consuming project loads `install-update-launcher.bash`, defines its manifest, and calls `iul_install` or `iul_update`:

```bash
IUL_PACKAGE_NAME="demo-launcher"
IUL_COMMAND_NAME="demo"
IUL_COMMAND_SOURCE="$SCRIPT_DIR/demo"
IUL_MODULE_SOURCE_DIR="$MODULE_DIR"
IUL_COMPLETION_SOURCE="$SCRIPT_DIR/completions/demo.bash"

iul_install false
iul_update false
```

The library manages user and system destinations, module copying, Bash completion, `PATH` setup for POSIX/Bash/Fish, and selective SHA-256 updates.

`iul_apply_from_git` downloads a package repository and applies an install or update from an explicit branch. This is the API used by `uni` to manage optional packages.

## Library installation

```bash
./install-update-launcher --install
./install-update-launcher --update
```

## Deployment channels

All launcher repositories use the same branch model:

| Channel | Branch | Purpose |
| --- | --- | --- |
| `stable` | `release` | production-ready commands |
| `prerelease` | `pre-release` | release candidates and user validation |
| `development` | `main` | active integration and development |

```bash
install-update-launcher --update --channel stable
install-update-launcher --update --channel prerelease
install-update-launcher --update --channel development
install-update-launcher --update --ref v1.2.0
```

The default channel is `stable`. `--ref` overrides the channel and accepts any Git branch or tag. `--update` downloads `https://github.com/dasbap/install-update-launcher.git`; set `INSTALL_UPDATE_LAUNCHER_REPOSITORY` to select another repository.

Changes are developed on `main`, promoted to `pre-release` after tests pass, then promoted to `release` after release-candidate validation. Stable releases are tagged as `vMAJOR.MINOR.PATCH`; prereleases use `vMAJOR.MINOR.PATCH-rc.N`.

Launchers can load the library directly from a sibling repository or through `INSTALL_UPDATE_LAUNCHER_LIB=/path/to/install-update-launcher.bash`.

## Tests

```bash
bash tests/run.sh
```
