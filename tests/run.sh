#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME
mkdir -p "$HOME" "$TMP/package/lib/demo" "$TMP/package/completions"

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

iul_install false >/dev/null
[[ -x "$HOME/.local/bin/demo" ]]
[[ -f "$HOME/.local/lib/demo/core.bash" ]]
[[ -f "$HOME/.local/lib/demo/install-update-launcher.bash" ]]
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
mkdir -p "$REMOTE/lib/remote-demo" "$REMOTE/completions"
cp "$TMP/package/demo" "$REMOTE/remote-demo"
cp "$TMP/package/lib/demo/core.bash" "$REMOTE/lib/remote-demo/core.bash"
cp "$TMP/package/completions/demo.bash" "$REMOTE/completions/remote-demo.bash"
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
[[ "$(iul_package_status_from_git false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash)" == up-to-date ]]
printf '\nchanged-installed=true\n' >> "$HOME/.local/lib/remote-demo/core.bash"
[[ "$(iul_package_status_from_git false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash)" == update-available ]]
rm -f "$HOME/.local/bin/remote-demo"
[[ "$(iul_package_status_from_git false "file://$REMOTE" release remote-demo remote-demo \
  remote-demo lib/remote-demo completions/remote-demo.bash)" == not-installed ]]

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
