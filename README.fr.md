# install-update-launcher

[English](README.md) | **Français**

Bibliothèque Bash partagée fournissant un comportement cohérent pour l'installation et la mise à jour des projets launcher.

## Intégration

Le projet consommateur charge `install-update-launcher.bash`, définit son manifeste puis appelle `iul_install` ou `iul_update` :

```bash
IUL_PACKAGE_NAME="demo-launcher"
IUL_COMMAND_NAME="demo"
IUL_COMMAND_SOURCE="$SCRIPT_DIR/demo"
IUL_MODULE_SOURCE_DIR="$MODULE_DIR"
IUL_COMPLETION_SOURCE="$SCRIPT_DIR/completions/demo.bash"

iul_install false
iul_update false
```

La bibliothèque gère les destinations utilisateur et système, la copie des modules, la complétion Bash, la configuration du `PATH` pour POSIX/Bash/Fish et les mises à jour sélectives par SHA-256.

## Installation de la bibliothèque

```bash
./install-update-launcher --install
./install-update-launcher --update
```

Les launchers peuvent charger la bibliothèque directement depuis un dépôt voisin ou avec `INSTALL_UPDATE_LAUNCHER_LIB=/path/to/install-update-launcher.bash`.

## Tests

```bash
bash tests/run.sh
```
