# install-update-launcher

[English](README.md) | **Français**

Bibliothèque Bash partagée fournissant un comportement cohérent pour l'installation et la mise à jour des projets launcher.

Ce paquet installe et met à jour uniquement son propre projet. L'installation de plusieurs projets launcher appartient à `uni-launcher`.

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

La sortie de mise à jour affiche uniquement les entrées modifiées : `Created`, `Updated` et `Deleted`. Les commandes, modules, manifestes et complétions inchangés restent silencieux. Les modules supprimés du paquet source sont également supprimés de l'installation.

`iul_apply_from_git` télécharge le dépôt d'un paquet et applique une installation ou une mise à jour depuis une branche explicite. Cette API est utilisée par `uni` pour gérer les paquets optionnels.

`iul_package_status_from_git` compare un paquet distant avec son installation et retourne `not-installed`, `up-to-date`, `update-available` ou `unavailable`.

## Sécurité des configurations

Les paquets déclarent `version`, `config_schema`, `config_min`, `config_max` et `config_dir` dans `deploy/manifest`. L'updater enregistre les métadonnées installées dans `~/.local/state/launcher-tools/packages`.

Les changements de schéma créent des sauvegardes persistantes dans `~/.local/state/launcher-tools/backups/<command>/`. Une transition incompatible s'arrête après la sauvegarde, sauf si la cible fournit `deploy/migrate-config` et que l'appel utilise `--merge-config`, ou si l'appel utilise explicitement `--force-config`.

```bash
install-update-launcher --update --ref v1.0.0
install-update-launcher --update --merge-config
install-update-launcher --update --force-config
```

Le hook de migration reçoit : le chemin de la configuration sauvegardée, le chemin de la configuration active, le schéma source et le schéma cible.

## Installation de la bibliothèque

```bash
./install-update-launcher --install
./install-update-launcher --update
```

## Canaux de déploiement

Tous les dépôts launcher utilisent le même modèle de branches :

| Canal | Branche | Utilisation |
| --- | --- | --- |
| `stable` | `release` | commandes prêtes pour la production |
| `prerelease` | `pre-release` | versions candidates et validation utilisateur |
| `development` | `main` | intégration active et développement |

```bash
install-update-launcher --update --channel stable
install-update-launcher --update --channel prerelease
install-update-launcher --update --channel development
install-update-launcher --update --ref v1.2.0
```

Le canal par défaut est `stable`. `--ref` remplace le canal et accepte une branche ou un tag Git. `--update` télécharge `https://github.com/dasbap/install-update-launcher.git`; utilisez `INSTALL_UPDATE_LAUNCHER_REPOSITORY` pour sélectionner un autre dépôt.

Les changements sont développés sur `main`, promus vers `pre-release` après validation des tests, puis vers `release` après validation de la version candidate. Les versions stables utilisent les tags `vMAJOR.MINOR.PATCH`; les préversions utilisent `vMAJOR.MINOR.PATCH-rc.N`.

Les launchers peuvent charger la bibliothèque directement depuis un dépôt voisin ou avec `INSTALL_UPDATE_LAUNCHER_LIB=/path/to/install-update-launcher.bash`.

## Tests

```bash
bash tests/run.sh
```
