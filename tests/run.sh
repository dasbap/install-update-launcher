#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME
mkdir -p "$HOME" "$TMP/package/lib/demo" "$TMP/package/completions" "$TMP/package/deploy"

fail() { echo "FAIL: $*" >&2; exit 1; }

cat > "$TMP/package/demo" <<'EOF'
#!/usr/bin/env bash
echo demo
EOF
cat > "$TMP/package/lib/demo/core.bash" <<'EOF'
demo_core=true
EOF
cat > "$TMP/package/completions/demo.bash" <<'EOF'
complete -W help demo
EOF
chmod +x "$TMP/package/demo"
cat > "$TMP/package/deploy/manifest" <<'EOF'
version=1.0.0
config_schema=0
config_min=0
config_max=0
config_dir=
EOF

source "$ROOT/lib/install-update-launcher/install-update-launcher.bash"
[[ "$(iul_channel_ref stable)" == release ]]
[[ "$(iul_channel_ref prerelease)" == pre-release ]]
[[ "$(iul_channel_ref development)" == main ]]
if iul_channel_ref invalid >/dev/null 2>&1; then
  fail "invalid deployment channel should fail"
fi
IUL_PACKAGE_NAME=demo-launcher
IUL_COMMAND_NAME=demo
IUL_COMMAND_SOURCE="$TMP/package/demo"
IUL_MODULE_SOURCE_DIR="$TMP/package/lib/demo"
IUL_COMPLETION_SOURCE="$TMP/package/completions/demo.bash"
IUL_MANIFEST_SOURCE="$TMP/package/deploy/manifest"

iul_install false >/dev/null
[[ -x "$HOME/.local/bin/demo" ]]
[[ -f "$HOME/.local/lib/demo/core.bash" ]]
[[ -f "$HOME/.local/lib/demo/install-update-launcher.bash" ]]
[[ -f "$HOME/.local/lib/demo/deploy.manifest" ]]
[[ -f "$HOME/.local/share/bash-completion/completions/demo" ]]
[[ "$(grep -Fc '# >>> launcher tools PATH >>>' "$HOME/.profile")" -eq 1 ]]

iul_install false >/dev/null
[[ "$(grep -Fc '# >>> launcher tools PATH >>>' "$HOME/.profile")" -eq 1 ]]
[[ "$(grep -Fc '# >>> demo launcher >>>' "$HOME/.bashrc")" -eq 1 ]]

IUL_COMMAND_SOURCE="$HOME/.local/bin/demo"
IUL_MODULE_SOURCE_DIR="$HOME/.local/lib/demo"
IUL_COMPLETION_SOURCE="$HOME/.local/share/bash-completion/completions/demo"
iul_install false >/dev/null
[[ -x "$HOME/.local/bin/demo" ]]
[[ -f "$HOME/.local/lib/demo/core.bash" ]]

IUL_COMMAND_SOURCE="$TMP/package/demo"
IUL_MODULE_SOURCE_DIR="$TMP/package/lib/demo"
IUL_COMPLETION_SOURCE="$TMP/package/completions/demo.bash"

printf '\nchanged=true\n' >> "$TMP/package/lib/demo/core.bash"
output="$(iul_update false)"
[[ "$output" == *"Updated module core.bash"* ]]
[[ "$output" == *"Unchanged command"* ]]

IUL_PACKAGE_NAME=second-launcher
IUL_COMMAND_NAME=second
IUL_COMMAND_SOURCE="$TMP/package/demo"
IUL_MODULE_SOURCE_DIR="$TMP/package/lib/demo"
IUL_COMPLETION_SOURCE=""
iul_install false >/dev/null
[[ "$(grep -Fc '# >>> launcher tools PATH >>>' "$HOME/.profile")" -eq 1 ]]
[[ "$(grep -Fc '# >>> launcher tools PATH >>>' "$HOME/.config/fish/config.fish")" -eq 1 ]]

REMOTE="$TMP/remote"
mkdir -p "$REMOTE/lib/remote-demo" "$REMOTE/completions" "$REMOTE/deploy"
cp "$TMP/package/demo" "$REMOTE/remote-demo"
cp "$TMP/package/lib/demo/core.bash" "$REMOTE/lib/remote-demo/core.bash"
cp "$TMP/package/completions/demo.bash" "$REMOTE/completions/remote-demo.bash"
cat > "$REMOTE/deploy/manifest" <<'EOF'
version=1.0.0
config_schema=1
config_min=1
config_max=1
config_dir=remote-demo
EOF
git -C "$REMOTE" init -q
git -C "$REMOTE" config user.name test
git -C "$REMOTE" config user.email test@example.invalid
git -C "$REMOTE" add -A
git -C "$REMOTE" commit -qm initial
git -C "$REMOTE" branch -M main
git -C "$REMOTE" branch release
git -C "$REMOTE" branch pre-release

iul_apply_from_git install false "file://$REMOTE" main remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash >/dev/null
[[ -x "$HOME/.local/bin/remote-demo" ]]
[[ -f "$HOME/.local/lib/remote-demo/core.bash" ]]
mkdir -p "$HOME/.config/remote-demo"
echo 'user-setting=keep' > "$HOME/.config/remote-demo/config"
[[ "$(iul_package_status_from_git false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash)" == up-to-date ]]
printf '\nchanged-installed=true\n' >> "$HOME/.local/lib/remote-demo/core.bash"
[[ "$(iul_package_status_from_git false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash)" == update-available ]]
rm -f "$HOME/.local/bin/remote-demo"
[[ "$(iul_package_status_from_git false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash)" == not-installed ]]

git -C "$REMOTE" checkout -qb schema2
cat > "$REMOTE/deploy/manifest" <<'EOF'
version=2.0.0
config_schema=2
config_min=2
config_max=2
config_dir=remote-demo
EOF
cat > "$REMOTE/deploy/migrate-config" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_config="$1"; destination="$2"
mkdir -p "$destination"
cp -a "$source_config/." "$destination/"
printf 'migrated=true\n' >> "$destination/config"
EOF
chmod +x "$REMOTE/deploy/migrate-config"
git -C "$REMOTE" add -A
git -C "$REMOTE" commit -qm schema2

iul_apply_from_git install false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash >/dev/null
mkdir -p "$HOME/.config/remote-demo"
echo 'user-setting=keep' > "$HOME/.config/remote-demo/config"
if iul_apply_from_git update false "file://$REMOTE" schema2 remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash >/dev/null 2>&1; then
  fail "incompatible schema update should require migration"
fi
find "$HOME/.local/state/launcher-tools/backups/remote-demo" -name metadata -print -quit | grep -q . || \
  fail "incompatible update did not create a backup"
IUL_MERGE_CONFIG=true
iul_apply_from_git update false "file://$REMOTE" schema2 remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash >/dev/null
grep -Fq 'migrated=true' "$HOME/.config/remote-demo/config"
grep -Fq 'config_schema=2' "$HOME/.local/state/launcher-tools/packages/remote-demo.state"
IUL_MERGE_CONFIG=false
if iul_apply_from_git update false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash >/dev/null 2>&1; then
  fail "incompatible downgrade should require --force-config"
fi
IUL_FORCE_CONFIG=true
iul_apply_from_git update false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash >/dev/null
grep -Fq 'config_schema=2' "$HOME/.local/state/launcher-tools/packages/remote-demo.state"
IUL_FORCE_CONFIG=false

SELF_REMOTE="$TMP/self-remote"
mkdir -p "$SELF_REMOTE/lib/install-update-launcher"
cp "$ROOT/install-update-launcher" "$SELF_REMOTE/install-update-launcher"
cp "$ROOT/lib/install-update-launcher/install-update-launcher.bash" \
  "$SELF_REMOTE/lib/install-update-launcher/install-update-launcher.bash"
printf '\nIUL_REMOTE_TEST=true\n' >> "$SELF_REMOTE/lib/install-update-launcher/install-update-launcher.bash"
git -C "$SELF_REMOTE" init -q
git -C "$SELF_REMOTE" config user.name test
git -C "$SELF_REMOTE" config user.email test@example.invalid
git -C "$SELF_REMOTE" add -A
git -C "$SELF_REMOTE" commit -qm initial
git -C "$SELF_REMOTE" branch -M main
git -C "$SELF_REMOTE" branch release
git -C "$SELF_REMOTE" branch pre-release

"$ROOT/install-update-launcher" --install >/dev/null
INSTALL_UPDATE_LAUNCHER_REPOSITORY="file://$SELF_REMOTE" \
  "$HOME/.local/bin/install-update-launcher" --update >/dev/null
grep -Fq 'IUL_REMOTE_TEST=true' "$HOME/.local/lib/install-update-launcher/install-update-launcher.bash"

bash -n "$ROOT/install-update-launcher" "$ROOT/lib/install-update-launcher/install-update-launcher.bash" "$ROOT/tests/run.sh"
"$ROOT/install-update-launcher" --help >/dev/null
echo "All tests passed."
