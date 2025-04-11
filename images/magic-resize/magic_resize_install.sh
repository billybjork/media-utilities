#!/usr/bin/env bash
set -euo pipefail

echo "🛠️  Installing the 'resize' command…"

# ---------------------------------------------------------------------
# 1.  Where we keep the real script
# ---------------------------------------------------------------------
TOOL_DIR="$HOME/.magic_resize"
TOOL_NAME="magic_resize.sh"
SCRIPT_PATH="$TOOL_DIR/$TOOL_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/billybjork/media-utilities/main/images/magic-resize/magic_resize.sh"

# ---------------------------------------------------------------------
# 2.  Pick (or create) a writable dir that is already on $PATH
# ---------------------------------------------------------------------
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

# ---------------------------------------------------------------------
# 3.  Fetch / refresh the real script
# ---------------------------------------------------------------------
echo "📥 Downloading core script to $SCRIPT_PATH"
mkdir -p "$TOOL_DIR"
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
echo "✅ Script downloaded and made executable."

# ---------------------------------------------------------------------
# 4.  Create (or refresh) the tiny wrapper on PATH
# ---------------------------------------------------------------------
WRAPPER_PATH="$BIN_DIR/resize"
cat >"$WRAPPER_PATH" <<EOF
#!/usr/bin/env bash
exec "$SCRIPT_PATH" "\$@"
EOF
chmod +x "$WRAPPER_PATH"
echo "✅ Wrapper installed at $WRAPPER_PATH"

# ---------------------------------------------------------------------
# 5.  Remove old aliases from shell rc files
# ---------------------------------------------------------------------
remove_alias_lines() {
  local rc_file="$1"
  if [[ -f "$rc_file" ]]; then
    # back up once, then strip any line that starts with alias resize=
    if grep -qE '^alias[[:space:]]+resize=' "$rc_file"; then
      cp "$rc_file" "$rc_file.bak.magic_resize.$(date +%s)"
      sed -i '' '/^alias[[:space:]]\+resize=/d' "$rc_file"
      echo "🧹 Removed old alias from $rc_file"
    fi
  fi
}
remove_alias_lines "$HOME/.zshrc"
remove_alias_lines "$HOME/.bashrc"
remove_alias_lines "$HOME/.bash_profile"

# Remove alias for this running shell (if it exists) and flush cache
unalias resize 2>/dev/null || true
command -v hash   &>/dev/null && hash   -r
command -v rehash &>/dev/null && rehash

# ---------------------------------------------------------------------
# 6.  Make sure ImageMagick exists (install Homebrew first if needed)
# ---------------------------------------------------------------------
echo "🔍 Checking for ImageMagick (magick/convert)…"
if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "⚠️  ImageMagick not found. Attempting automatic install."

  # Install (or locate) Homebrew
  if ! command -v brew >/dev/null 2>&1; then
    echo "🍺 Homebrew not found – installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ "$(uname -m)" == "arm64" ]]; then
      export PATH="/opt/homebrew/bin:$PATH"
    else
      export PATH="/usr/local/bin:$PATH"
    fi
    echo "✅ Homebrew installed."
  else
    echo "🍺 Homebrew already present."
  fi

  echo "📦 Installing ImageMagick via Homebrew…"
  brew install imagemagick
  echo "✅ ImageMagick installed."
else
  echo "✅ ImageMagick already available."
fi

# ---------------------------------------------------------------------
# 7.  Done!
# ---------------------------------------------------------------------
echo ""
echo "🎉 Setup complete!  You can use the command immediately:"
echo "   resize my_image.jpg"
echo "   resize --1x1 my_folder/"
echo ""
echo "No need to restart or run 'source'. Have fun! 🚀"

exit 0