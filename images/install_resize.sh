#!/bin/bash

echo "🛠️  Setting up 'resize' image tool..."

# --- Step 1: Set up script location and download ---
TOOL_DIR="$HOME/.resize_tool"
SCRIPT_PATH="$TOOL_DIR/resize"
SCRIPT_URL="https://raw.githubusercontent.com/billybjork/media-utilities/main/images/smart_letterbox.sh"

mkdir -p "$TOOL_DIR"

# Download script (update URL to actual hosted version)
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH" || {
  echo "❌ Failed to download script. Check the URL."; exit 1;
}

chmod +x "$SCRIPT_PATH"

# --- Step 2: Add alias to shell config ---
SHELL_RC="$HOME/.zshrc"
ALIAS_CMD='alias resize="$HOME/.resize_tool/resize"'

if ! grep -Fxq "$ALIAS_CMD" "$SHELL_RC"; then
  echo "$ALIAS_CMD" >> "$SHELL_RC"
  echo "✅ Alias 'resize' added to $SHELL_RC"
else
  echo "ℹ️ Alias already exists in $SHELL_RC"
fi

# --- Step 3: Check if ImageMagick is installed ---
if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "🧙 ImageMagick not found. You need it to run this tool."

  read -p "❓ Do you want to install ImageMagick via Homebrew? [Y/n]: " answer
  answer=${answer:-Y}

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "🍺 Homebrew not found. Installing Homebrew first..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        echo "❌ Failed to install Homebrew."; exit 1;
      }
    fi

    echo "📦 Installing ImageMagick..."
    brew install imagemagick || {
      echo "❌ Failed to install ImageMagick."; exit 1;
    }
    echo "✅ ImageMagick installed!"
  else
    echo "⚠️ Skipping ImageMagick install. You must install it before using 'resize'."
  fi
else
  echo "✅ ImageMagick is already installed."
fi

# --- Step 4: Finalize ---
source "$SHELL_RC"
echo "🎉 Setup complete! You can now run: resize /path/to/image.jpg"
