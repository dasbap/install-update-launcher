# install-update-launcher

Bibliotheque Bash partagee pour installer et mettre a jour les projets launcher avec le meme comportement.

## Integration

Le projet consommateur charge `install-update-launcher.bash`, renseigne le manifeste puis appelle `iul_install` ou `iul_update`:

```bash
IUL_PACKAGE_NAME="demo-launcher"
IUL_COMMAND_NAME="demo"
IUL_COMMAND_SOURCE="$SCRIPT_DIR/demo"
IUL_MODULE_SOURCE_DIR="$MODULE_DIR"
IUL_COMPLETION_SOURCE="$SCRIPT_DIR/completions/demo.bash"

iul_install false
iul_update false
```

La bibliotheque gere les destinations utilisateur et systeme, la copie des modules, la completion Bash, le `PATH` pour POSIX/Bash/Fish et les mises a jour selectives par SHA-256.

## Installation de la bibliotheque

```bash
./install-update-launcher --install
./install-update-launcher --update
```

Les launchers peuvent aussi charger la bibliotheque directement depuis un depot frere ou via `INSTALL_UPDATE_LAUNCHER_LIB=/chemin/install-update-launcher.bash`.

## Tests

```bash
bash tests/run.sh
```
