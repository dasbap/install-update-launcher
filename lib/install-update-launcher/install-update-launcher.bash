#!/usr/bin/env bash

IUL_LIBRARY_FILE="${BASH_SOURCE[0]}"

iul_require_manifest() {
  local variable
  for variable in IUL_PACKAGE_NAME IUL_COMMAND_NAME IUL_COMMAND_SOURCE IUL_MODULE_SOURCE_DIR; do
    [[ -n "${!variable:-}" ]] || {
      echo "Erreur: manifeste incomplet, variable $variable manquante" >&2
      return 1
    }
  done
}

iul_install_paths() {
  local system="$1"
  if [[ "$system" == true ]]; then
    printf '/usr/local/bin\n/usr/local/lib/%s\n/usr/local/share/bash-completion/completions\n' "$IUL_COMMAND_NAME"
  else
    printf '%s/.local/bin\n%s/.local/lib/%s\n%s/.local/share/bash-completion/completions\n' \
      "$HOME" "$HOME" "$IUL_COMMAND_NAME" "$HOME"
  fi
}

iul_read_paths() {
  local paths
  paths="$(iul_install_paths "$1")"
  IUL_BIN_DEST="${paths%%$'\n'*}"
  paths="${paths#*$'\n'}"
  IUL_LIB_DEST="${paths%%$'\n'*}"
  IUL_COMPLETION_DEST="${paths#*$'\n'}"
}

iul_append_once() {
  local file="$1" marker="$2" content="$3"
  touch "$file"
  grep -Fq "$marker" "$file" && return 0
  printf '\n%s\n' "$content" >> "$file"
}

iul_configure_user_shells() {
  local completion_file="$HOME/.local/share/bash-completion/completions/$IUL_COMMAND_NAME"
  local profile_block bash_block fish_block

  profile_block='# >>> launcher tools PATH >>>
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
# <<< launcher tools PATH <<<'
  iul_append_once "$HOME/.profile" '# >>> launcher tools PATH >>>' "$profile_block"

  bash_block="# >>> $IUL_COMMAND_NAME launcher >>>
case \":\$PATH:\" in
  *\":\$HOME/.local/bin:\"*) ;;
  *) export PATH=\"\$HOME/.local/bin:\$PATH\" ;;
esac
if [[ -f \"$completion_file\" ]]; then
  source \"$completion_file\"
fi
# <<< $IUL_COMMAND_NAME launcher <<<"
  iul_append_once "$HOME/.bashrc" "# >>> $IUL_COMMAND_NAME launcher >>>" "$bash_block"

  fish_block='# >>> launcher tools PATH >>>
fish_add_path "$HOME/.local/bin"
# <<< launcher tools PATH <<<'
  mkdir -p "$HOME/.config/fish"
  iul_append_once "$HOME/.config/fish/config.fish" '# >>> launcher tools PATH >>>' "$fish_block"
}

iul_hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Erreur: sha256sum ou shasum est requis pour mettre a jour $IUL_PACKAGE_NAME" >&2
    return 1
  fi
}

iul_copy_if_changed() {
  local source="$1" destination="$2" label="$3"
  if [[ -f "$destination" && "$(iul_hash_file "$source")" == "$(iul_hash_file "$destination")" ]]; then
    echo "Unchanged $label"
    return 1
  fi
  cp "$source" "$destination"
  echo "Updated $label"
}

iul_copy_modules() {
  local destination="$1" module
  [[ "$IUL_MODULE_SOURCE_DIR" -ef "$destination" ]] && return 0
  for module in "$IUL_MODULE_SOURCE_DIR"/*.bash; do
    [[ -e "$module" ]] || continue
    cp "$module" "$destination/"
  done
  if [[ ! -f "$IUL_MODULE_SOURCE_DIR/install-update-launcher.bash" ]] && \
     { [[ ! -e "$destination/install-update-launcher.bash" ]] || ! "$IUL_LIBRARY_FILE" -ef "$destination/install-update-launcher.bash"; }; then
    cp "$IUL_LIBRARY_FILE" "$destination/install-update-launcher.bash"
  fi
}

iul_install() {
  local system="$1" module modules_are_installed=false
  iul_require_manifest || return 1
  iul_read_paths "$system"
  mkdir -p "$IUL_BIN_DEST" "$IUL_LIB_DEST" "$IUL_COMPLETION_DEST"
  [[ "$IUL_MODULE_SOURCE_DIR" -ef "$IUL_LIB_DEST" ]] && modules_are_installed=true
  if [[ -e "$IUL_BIN_DEST/$IUL_COMMAND_NAME" && "$IUL_COMMAND_SOURCE" -ef "$IUL_BIN_DEST/$IUL_COMMAND_NAME" ]]; then
    :
  else
    rm -f "$IUL_BIN_DEST/$IUL_COMMAND_NAME"
    cp "$IUL_COMMAND_SOURCE" "$IUL_BIN_DEST/$IUL_COMMAND_NAME"
  fi
  if [[ "$modules_are_installed" == false ]]; then
    for module in "$IUL_LIB_DEST"/*.bash; do
      [[ -e "$module" ]] && rm -f "$module"
    done
  fi
  iul_copy_modules "$IUL_LIB_DEST"
  if [[ -n "${IUL_COMPLETION_SOURCE:-}" ]]; then
    if [[ ! -e "$IUL_COMPLETION_DEST/$IUL_COMMAND_NAME" || ! "$IUL_COMPLETION_SOURCE" -ef "$IUL_COMPLETION_DEST/$IUL_COMMAND_NAME" ]]; then
      cp "$IUL_COMPLETION_SOURCE" "$IUL_COMPLETION_DEST/$IUL_COMMAND_NAME"
    fi
  else
    rm -f "$IUL_COMPLETION_DEST/$IUL_COMMAND_NAME"
  fi
  chmod +x "$IUL_BIN_DEST/$IUL_COMMAND_NAME"
  [[ "$system" == true ]] || iul_configure_user_shells
  echo "Installed $IUL_PACKAGE_NAME to $IUL_BIN_DEST/$IUL_COMMAND_NAME"
  echo "Installed $IUL_PACKAGE_NAME modules to $IUL_LIB_DEST"
  if [[ -n "${IUL_COMPLETION_SOURCE:-}" ]]; then
    echo "Installed $IUL_PACKAGE_NAME Bash completion to $IUL_COMPLETION_DEST/$IUL_COMMAND_NAME"
  fi
}

iul_update() {
  local system="$1" module module_name changed=false
  iul_require_manifest || return 1
  iul_read_paths "$system"
  mkdir -p "$IUL_BIN_DEST" "$IUL_LIB_DEST" "$IUL_COMPLETION_DEST"

  if iul_copy_if_changed "$IUL_COMMAND_SOURCE" "$IUL_BIN_DEST/$IUL_COMMAND_NAME" "command $IUL_BIN_DEST/$IUL_COMMAND_NAME"; then
    chmod +x "$IUL_BIN_DEST/$IUL_COMMAND_NAME"
    changed=true
  fi
  for module in "$IUL_MODULE_SOURCE_DIR"/*.bash; do
    [[ -e "$module" ]] || continue
    module_name="$(basename "$module")"
    iul_copy_if_changed "$module" "$IUL_LIB_DEST/$module_name" "module $module_name" && changed=true || true
  done
  if [[ ! -f "$IUL_MODULE_SOURCE_DIR/install-update-launcher.bash" ]]; then
    iul_copy_if_changed "$IUL_LIBRARY_FILE" "$IUL_LIB_DEST/install-update-launcher.bash" "shared installer library" && changed=true || true
  fi
  if [[ -n "${IUL_COMPLETION_SOURCE:-}" ]]; then
    iul_copy_if_changed "$IUL_COMPLETION_SOURCE" "$IUL_COMPLETION_DEST/$IUL_COMMAND_NAME" "Bash completion $IUL_COMPLETION_DEST/$IUL_COMMAND_NAME" && changed=true || true
  fi
  [[ "$system" == true ]] || iul_configure_user_shells
  if [[ "$changed" == false ]]; then
    echo "$IUL_PACKAGE_NAME is already up to date"
  else
    echo "$IUL_PACKAGE_NAME update complete"
  fi
}

iul_apply_from_git() {
  local action="$1" system="$2" repository="$3" ref="$4" package_name="$5"
  local command_name="$6" command_path="$7" modules_path="$8" completion_path="${9:-}"
  local checkout

  command -v git >/dev/null 2>&1 || {
    echo "Error: git is required to download $package_name" >&2
    return 1
  }
  checkout="$(mktemp -d)"
  if ! git clone --quiet --depth 1 --branch "$ref" "$repository" "$checkout"; then
    rm -rf "$checkout"
    echo "Error: unable to download $package_name from $repository ($ref)" >&2
    return 1
  fi

  IUL_PACKAGE_NAME="$package_name"
  IUL_COMMAND_NAME="$command_name"
  IUL_COMMAND_SOURCE="$checkout/$command_path"
  IUL_MODULE_SOURCE_DIR="$checkout/$modules_path"
  if [[ -n "$completion_path" ]]; then
    IUL_COMPLETION_SOURCE="$checkout/$completion_path"
  else
    IUL_COMPLETION_SOURCE=""
  fi

  local status=0
  case "$action" in
    install) iul_install "$system" || status=$? ;;
    update) iul_update "$system" || status=$? ;;
    *) status=1; echo "Error: unsupported repository action: $action" >&2 ;;
  esac
  rm -rf "$checkout"
  return "$status"
}
