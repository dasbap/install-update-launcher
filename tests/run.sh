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

bash -n "$ROOT/install-update-launcher" "$ROOT/lib/install-update-launcher/install-update-launcher.bash" "$ROOT/tests/run.sh"
"$ROOT/install-update-launcher" --help >/dev/null
echo "All tests passed."
