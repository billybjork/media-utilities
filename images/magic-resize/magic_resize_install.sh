#!/usr/bin/env bash
# magic_resize_install.sh
# Installs the “resize” command (magic‑resize) so it works immediately,
# bootstraps Homebrew + ImageMagick if needed, removes any old aliases,
# and fixes PATH for the current and future shells.

set -euo pipefail

echo "🛠️  Installing the 'resize' command…"

# ──────────────────────────────────────────────────────────────────────
# 1.  Where we keep the real script
# ──────────────────────────────────────────────────────────────────────
TOOL_DIR="$HOME/.magic_resize"
TOOL_NAME="magic_resize.sh"
SCRIPT_PATH="$TOOL_DIR/$TOOL_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/billybjork/media-utilities/main/images/magic-resize/magic_resize.sh"

# ──────────────────────────────────────────────────────────────────────
# 2.  Choose (or create) a writable dir that is already on PATH
#     priority: ~/.local/bin → /usr/local/bin → /opt/homebrew/bin
# ──────────────────────────────────────────────────────────────────────
BIN_DIR=""
for d in "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin"; do
  if [[ ":$PATH:" == *":$d:"* ]] && [[ -w "$d" ]]; then
    BIN_DIR="$d" && break
  fi
done
if [[ -z $BIN_DIR ]]; then
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR:$PATH"
  echo "🔧 Added $BIN_DIR to PATH for this session."
fi
echo "📂 Wrapper will be installed to: $BIN_DIR"

# ──────────────────────────────────────────────────────────────────────
# 3.  Fetch / refresh the real script
# ──────────────────────────────────────────────────────────────────────
echo "📥 Downloading core script to $SCRIPT_PATH"
mkdir -p "$TOOL_DIR"
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
echo "✅ Script downloaded and made executable."

# ──────────────────────────────────────────────────────────────────────
# 4.  Create (or refresh) the tiny wrapper on PATH
# ──────────────────────────────────────────────────────────────────────
WRAPPER_PATH="$BIN_DIR/resize"
cat >"$WRAPPER_PATH" <<EOF
#!/usr/bin/env bash
exec "$SCRIPT_PATH" "\$@"
EOF
chmod +x "$WRAPPER_PATH"
echo "✅ Wrapper installed at $WRAPPER_PATH"

# ──────────────────────────────────────────────────────────────────────
# 5.  Ensure BIN_DIR is on PATH for future shells
# ──────────────────────────────────────────────────────────────────────
add_path_line() {
  local rc_file="$1"
  if [[ -f "$rc_file" ]] && ! grep -qF "$BIN_DIR" "$rc_file"; then
    {
      echo ""
      echo "# Added by magic‑resize installer – wrapper location"
      echo "export PATH=\"$BIN_DIR:\$PATH\""
    } >> "$rc_file"
    echo "🛠️  Added $BIN_DIR to PATH in $rc_file"
  fi
}
add_path_line "$HOME/.zshrc"
add_path_line "$HOME/.bashrc"
add_path_line "$HOME/.zprofile"
add_path_line "$HOME/.bash_profile"

# ──────────────────────────────────────────────────────────────────────
# 6.  Remove any old 'resize' aliases
# ──────────────────────────────────────────────────────────────────────
remove_alias_lines() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] || return
  if grep -qE '^alias[[:space:]]+resize=' "$rc_file"; then
    cp "$rc_file" "$rc_file.bak.magic_resize.$(date +%s)"
    sed -i '' '/^alias[[:space:]]\+resize=/d' "$rc_file"
    echo "🧹 Removed old alias from $rc_file"
  fi
}
remove_alias_lines "$HOME/.zshrc"
remove_alias_lines "$HOME/.bashrc"
remove_alias_lines "$HOME/.bash_profile"

unalias resize 2>/dev/null || true
command -v hash   &>/dev/null && hash   -r
command -v rehash &>/dev/null && rehash

# ──────────────────────────────────────────────────────────────────────
# 7.  Make sure ImageMagick exists (install Homebrew first if needed)
# ──────────────────────────────────────────────────────────────────────
echo "🔍 Checking for ImageMagick (magick/convert)…"
if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "⚠️  ImageMagick not found. Attempting automatic install."

  # ── Install (or locate) Homebrew ───────────────────────────────────
  if ! command -v brew >/dev/null 2>&1; then
    echo "🍺 Homebrew not found – installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  echo "🍺 Homebrew present."

  # ── Ensure Homebrew's bin dir is on PATH now & later ───────────────
  BREW_PREFIX="$(brew --prefix)"
  if [[ ":$PATH:" != *":$BREW_PREFIX/bin:"* ]]; then
    export PATH="$BREW_PREFIX/bin:$PATH"
    for rc in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
      [[ -f "$rc" ]] || continue
      grep -qF "$BREW_PREFIX/bin" "$rc" && continue
      {
        echo ""
        echo "# Added by magic‑resize installer – Homebrew bin"
        echo "export PATH=\"$BREW_PREFIX/bin:\$PATH\""
      } >> "$rc"
    done
    echo "🛠️  Added $BREW_PREFIX/bin to PATH (current session and future shells)."
  fi

  # ── Install ImageMagick ────────────────────────────────────────────
  echo "📦 Installing ImageMagick via Homebrew…"
  brew install imagemagick
  echo "✅ ImageMagick installed."
else
  echo "✅ ImageMagick already available."
fi

# ──────────────────────────────────────────────────────────────────────
# 8.  Finished
# ──────────────────────────────────────────────────────────────────────
echo ""
echo "🎉 Setup complete!  You can use magic‑resize with commands like:"
echo "   resize my_image.jpg"
echo "   resize my_folder/"
echo "   resize --9x16 my_folder/"

exit 0