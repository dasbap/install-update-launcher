#!/usr/bin/env bash

IUL_LIBRARY_FILE="${BASH_SOURCE[0]}"
IUL_MERGE_CONFIG="${IUL_MERGE_CONFIG:-false}"
IUL_FORCE_CONFIG="${IUL_FORCE_CONFIG:-false}"

iul_channel_ref() {
  case "$1" in
    stable) printf 'release\n' ;;
    prerelease) printf 'pre-release\n' ;;
    development) printf 'main\n' ;;
    *) echo "Error: unknown deployment channel: $1" >&2; return 2 ;;
  esac
}

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

iul_state_dir() {
  if [[ "$1" == true ]]; then
    printf '/var/lib/launcher-tools\n'
  else
    printf '%s/launcher-tools\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
  fi
}

iul_read_manifest() {
  local manifest="$1" line key value
  IUL_TARGET_VERSION="0.0.0"
  IUL_TARGET_CONFIG_SCHEMA="0"
  IUL_TARGET_CONFIG_MIN="0"
  IUL_TARGET_CONFIG_MAX="0"
  IUL_TARGET_CONFIG_DIR="${IUL_CONFIG_DIR_FALLBACK:-}"
  [[ -f "$manifest" ]] || return 0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    case "$key" in
      version) IUL_TARGET_VERSION="$value" ;;
      config_schema) IUL_TARGET_CONFIG_SCHEMA="$value" ;;
      config_min) IUL_TARGET_CONFIG_MIN="$value" ;;
      config_max) IUL_TARGET_CONFIG_MAX="$value" ;;
      config_dir) IUL_TARGET_CONFIG_DIR="$value" ;;
    esac
  done < "$manifest"
}

iul_read_installed_state() {
  local state_file="$1" line key value
  IUL_INSTALLED_VERSION="unknown"
  IUL_INSTALLED_CONFIG_SCHEMA="0"
  [[ -f "$state_file" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    case "$key" in
      version) IUL_INSTALLED_VERSION="$value" ;;
      config_schema) IUL_INSTALLED_CONFIG_SCHEMA="$value" ;;
    esac
  done < "$state_file"
}

iul_write_installed_state() {
  local system="$1" state_dir state_file
  state_dir="$(iul_state_dir "$system")/packages"
  state_file="$state_dir/$IUL_COMMAND_NAME.state"
  mkdir -p "$state_dir"
  printf 'version=%s\nconfig_schema=%s\nref=%s\n' \
    "$IUL_TARGET_VERSION" "${IUL_RESULT_CONFIG_SCHEMA:-$IUL_TARGET_CONFIG_SCHEMA}" \
    "${IUL_TARGET_REF:-unknown}" > "$state_file"
}

iul_config_path() {
  [[ -n "$IUL_TARGET_CONFIG_DIR" ]] || return 1
  if [[ "$1" == true ]]; then
    printf '/etc/%s\n' "$IUL_TARGET_CONFIG_DIR"
  else
    printf '%s/%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}" "$IUL_TARGET_CONFIG_DIR"
  fi
}

iul_backup_config() {
  local system="$1" reason="$2" config_path state_dir backup_dir timestamp
  config_path="$(iul_config_path "$system")" || return 0
  [[ -e "$config_path" ]] || return 0
  state_dir="$(iul_state_dir "$system")"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$state_dir/backups/$IUL_COMMAND_NAME"
  backup_dir="$(mktemp -d "$state_dir/backups/$IUL_COMMAND_NAME/${timestamp}-schema-${IUL_INSTALLED_CONFIG_SCHEMA}-version-${IUL_INSTALLED_VERSION}.XXXXXX")"
  cp -a "$config_path" "$backup_dir/config"
  printf 'reason=%s\nsource_schema=%s\ntarget_schema=%s\nsource_version=%s\ntarget_version=%s\n' \
    "$reason" "$IUL_INSTALLED_CONFIG_SCHEMA" "$IUL_TARGET_CONFIG_SCHEMA" \
    "$IUL_INSTALLED_VERSION" "$IUL_TARGET_VERSION" > "$backup_dir/metadata"
  IUL_LAST_CONFIG_BACKUP="$backup_dir"
  echo "Backed up $IUL_PACKAGE_NAME configuration to $backup_dir"
}

iul_prepare_config_transition() {
  local system="$1" checkout="$2" state_file config_path migration_hook
  local incompatible=false schema_changed=false
  IUL_LAST_CONFIG_BACKUP=""
  IUL_RESULT_CONFIG_SCHEMA="$IUL_TARGET_CONFIG_SCHEMA"
  state_file="$(iul_state_dir "$system")/packages/$IUL_COMMAND_NAME.state"
  iul_read_paths "$system"
  if [[ ! -x "$IUL_BIN_DEST/$IUL_COMMAND_NAME" ]]; then
    IUL_INSTALLED_VERSION="none"
    IUL_INSTALLED_CONFIG_SCHEMA="$IUL_TARGET_CONFIG_SCHEMA"
    return 0
  fi
  iul_read_installed_state "$state_file"
  if [[ ! -f "$state_file" ]]; then
    IUL_INSTALLED_VERSION="legacy"
    IUL_INSTALLED_CONFIG_SCHEMA="$IUL_TARGET_CONFIG_SCHEMA"
  fi
  IUL_RESULT_CONFIG_SCHEMA="$IUL_INSTALLED_CONFIG_SCHEMA"
  [[ "$IUL_INSTALLED_CONFIG_SCHEMA" == "$IUL_TARGET_CONFIG_SCHEMA" ]] || schema_changed=true
  if (( IUL_INSTALLED_CONFIG_SCHEMA < IUL_TARGET_CONFIG_MIN || IUL_INSTALLED_CONFIG_SCHEMA > IUL_TARGET_CONFIG_MAX )); then
    incompatible=true
  fi
  if [[ "$schema_changed" == true ]]; then
    iul_backup_config "$system" "$([[ "$incompatible" == true ]] && printf incompatible || printf schema-change)"
  fi
  if [[ "$IUL_MERGE_CONFIG" == true && "$schema_changed" == true ]]; then
    [[ -n "$IUL_LAST_CONFIG_BACKUP" ]] || return 0
    migration_hook="$checkout/deploy/migrate-config"
    config_path="$(iul_config_path "$system")" || return 0
    if [[ -x "$migration_hook" ]]; then
      "$migration_hook" "$IUL_LAST_CONFIG_BACKUP/config" "$config_path" \
        "$IUL_INSTALLED_CONFIG_SCHEMA" "$IUL_TARGET_CONFIG_SCHEMA"
      IUL_RESULT_CONFIG_SCHEMA="$IUL_TARGET_CONFIG_SCHEMA"
      echo "Merged $IUL_PACKAGE_NAME configuration with deploy/migrate-config"
    else
      echo "Error: --merge-config requested but $IUL_PACKAGE_NAME provides no deploy/migrate-config hook" >&2
      return 4
    fi
  fi
  if [[ "$incompatible" == true && "$IUL_MERGE_CONFIG" != true && "$IUL_FORCE_CONFIG" != true ]]; then
    echo "Error: configuration schema $IUL_INSTALLED_CONFIG_SCHEMA is incompatible with $IUL_PACKAGE_NAME $IUL_TARGET_VERSION (supported: $IUL_TARGET_CONFIG_MIN-$IUL_TARGET_CONFIG_MAX)." >&2
    if [[ -x "$checkout/deploy/migrate-config" ]]; then
      echo "A backup was kept. Re-run with --merge-config to use the package migration hook." >&2
    else
      echo "A backup was kept. Use a compatible --ref or --force-config after reviewing the configuration." >&2
    fi
    return 3
  fi
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
  if [[ -n "${IUL_MANIFEST_SOURCE:-}" && -f "$IUL_MANIFEST_SOURCE" ]] && \
     { [[ ! -e "$destination/deploy.manifest" ]] || ! [[ "$IUL_MANIFEST_SOURCE" -ef "$destination/deploy.manifest" ]]; }; then
    cp "$IUL_MANIFEST_SOURCE" "$destination/deploy.manifest"
  fi
  if [[ ! -f "$IUL_MODULE_SOURCE_DIR/install-update-launcher.bash" ]] && \
     { [[ ! -e "$destination/install-update-launcher.bash" ]] || ! [[ "$IUL_LIBRARY_FILE" -ef "$destination/install-update-launcher.bash" ]]; }; then
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
  if [[ -n "${IUL_MANIFEST_SOURCE:-}" ]]; then
    iul_read_manifest "$IUL_MANIFEST_SOURCE"
    IUL_RESULT_CONFIG_SCHEMA="$IUL_TARGET_CONFIG_SCHEMA"
    IUL_TARGET_REF="${IUL_TARGET_REF:-local}"
    iul_write_installed_state "$system"
  fi
  echo "Installed $IUL_PACKAGE_NAME to $IUL_BIN_DEST/$IUL_COMMAND_NAME"
  echo "Installed $IUL_PACKAGE_NAME modules to $IUL_LIB_DEST"
  if [[ -n "${IUL_COMPLETION_SOURCE:-}" ]]; then
    echo "Installed $IUL_PACKAGE_NAME Bash completion to $IUL_COMPLETION_DEST/$IUL_COMMAND_NAME"
  fi
}

iul_clone_ref() {
  local repository="$1" ref="$2" checkout="$3"
  git init -q "$checkout" || return 1
  git -C "$checkout" remote add origin "$repository" || return 1
  git -C "$checkout" fetch --quiet --depth 1 origin "$ref" || return 1
  git -C "$checkout" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD || return 1
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
  if [[ -n "${IUL_MANIFEST_SOURCE:-}" && -f "$IUL_MANIFEST_SOURCE" ]]; then
    iul_copy_if_changed "$IUL_MANIFEST_SOURCE" "$IUL_LIB_DEST/deploy.manifest" "deployment manifest" && changed=true || true
  fi
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
  if ! iul_clone_ref "$repository" "$ref" "$checkout"; then
    rm -rf "$checkout"
    echo "Error: unable to download $package_name from $repository ($ref)" >&2
    return 1
  fi

  IUL_PACKAGE_NAME="$package_name"
  IUL_COMMAND_NAME="$command_name"
  IUL_COMMAND_SOURCE="$checkout/$command_path"
  IUL_MODULE_SOURCE_DIR="$checkout/$modules_path"
  IUL_MANIFEST_SOURCE="$checkout/deploy/manifest"
  IUL_TARGET_REF="$ref"
  iul_read_manifest "$checkout/deploy/manifest"
  if [[ -n "$completion_path" ]]; then
    IUL_COMPLETION_SOURCE="$checkout/$completion_path"
  else
    IUL_COMPLETION_SOURCE=""
  fi

  local status=0
  if [[ "$action" == update ]]; then
    iul_prepare_config_transition "$system" "$checkout" || status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    rm -rf "$checkout"
    return "$status"
  fi
  case "$action" in
    install) iul_install "$system" || status=$? ;;
    update) iul_update "$system" || status=$? ;;
    *) status=1; echo "Error: unsupported repository action: $action" >&2 ;;
  esac
  [[ "$status" -ne 0 ]] || iul_write_installed_state "$system"
  rm -rf "$checkout"
  return "$status"
}

iul_package_status_from_git() {
  local system="$1" repository="$2" ref="$3" package_name="$4"
  local command_name="$5" command_path="$6" modules_path="$7" completion_path="${8:-}"
  local checkout module module_name status="up-to-date"

  command -v git >/dev/null 2>&1 || {
    printf 'unavailable\n'
    return 0
  }
  checkout="$(mktemp -d)"
  if ! iul_clone_ref "$repository" "$ref" "$checkout"; then
    rm -rf "$checkout"
    printf 'unavailable\n'
    return 0
  fi

  IUL_PACKAGE_NAME="$package_name"
  IUL_COMMAND_NAME="$command_name"
  iul_read_manifest "$checkout/deploy/manifest"
  iul_read_paths "$system"
  if [[ ! -x "$IUL_BIN_DEST/$command_name" ]]; then
    rm -rf "$checkout"
    printf 'not-installed\n'
    return 0
  fi
  iul_read_installed_state "$(iul_state_dir "$system")/packages/$command_name.state"
  if [[ "$IUL_INSTALLED_VERSION" != "$IUL_TARGET_VERSION" || \
        "$IUL_INSTALLED_CONFIG_SCHEMA" != "$IUL_TARGET_CONFIG_SCHEMA" ]]; then
    status="update-available"
  fi

  if [[ "$(iul_hash_file "$checkout/$command_path")" != "$(iul_hash_file "$IUL_BIN_DEST/$command_name")" ]]; then
    status="update-available"
  fi
  for module in "$checkout/$modules_path"/*.bash; do
    [[ -e "$module" ]] || continue
    module_name="$(basename "$module")"
    if [[ ! -f "$IUL_LIB_DEST/$module_name" ]] || \
       [[ "$(iul_hash_file "$module")" != "$(iul_hash_file "$IUL_LIB_DEST/$module_name")" ]]; then
      status="update-available"
      break
    fi
  done
  if [[ -n "$completion_path" ]] && \
     { [[ ! -f "$IUL_COMPLETION_DEST/$command_name" ]] || \
       [[ "$(iul_hash_file "$checkout/$completion_path")" != "$(iul_hash_file "$IUL_COMPLETION_DEST/$command_name")" ]]; }; then
    status="update-available"
  fi

  rm -rf "$checkout"
  printf '%s\n' "$status"
}
