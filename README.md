# install-update-launcher

**English** | [Français](README.fr.md)

Shared Bash library providing consistent installation and update behavior for launcher projects.

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

## Library installation

```bash
./install-update-launcher --install
./install-update-launcher --update
```

Launchers can load the library directly from a sibling repository or through `INSTALL_UPDATE_LAUNCHER_LIB=/path/to/install-update-launcher.bash`.

## Tests

```bash
bash tests/run.sh
```
