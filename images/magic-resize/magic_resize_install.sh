#!/bin/bash

echo "🛠️  Setting up magic-resize..."

# --- Step 1: Set up script location and download ---
TOOL_DIR="$HOME/.resize_tool"
SCRIPT_PATH="$TOOL_DIR/resize"
SCRIPT_URL="https://raw.githubusercontent.com/billybjork/media-utilities/main/images/magic-resize/magic_resize.sh"

mkdir -p "$TOOL_DIR"

# Download script (update URL to actual hosted version)
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH" || {
  echo "❌ Failed to download script. Check the URL."; exit 1;
}

chmod +x "$SCRIPT_PATH"

# --- Step 2: Add alias to shell config ---
# Define the alias command string
ALIAS_COMMAND="alias $ALIAS_NAME='$ALIAS_TARGET_PATH'" # Uses the variable!
CONFIG_CHANGED=0

# Function to add alias if not present
add_alias() {
    local rc_file="$1"
    local shell_name="$2"
    if [ -f "$rc_file" ]; then
      # Check specifically for the CORRECT alias command string
      if ! grep -Fxq "$ALIAS_COMMAND" "$rc_file"; then
        # Optional: Remove any OLD incorrect alias definitions first
        # Use sed to delete lines containing 'alias resize=' that point to the old path (use a unique part of the old path)
        # Be careful with sed -i on macOS vs Linux if compatibility is needed, but for direct user run, this might be okay:
        sed -i.bak "/alias ${ALIAS_NAME}=.*magic-resize/d" "$rc_file"

        echo "" >> "$rc_file" # Add newline for separation
        echo "# Alias for smart image resize tool ($TOOL_NAME)" >> "$rc_file"
        echo "$ALIAS_COMMAND" >> "$rc_file" # Add the CORRECT alias
        echo "✅ Alias '$ALIAS_NAME' added/corrected in $rc_file"
        CONFIG_CHANGED=1
      else
        echo "✅ Correct alias '$ALIAS_NAME' already exists in $rc_file"
      fi
    else
        echo "ℹ️ $rc_file not found (normal if you primarily use $shell_name)."
    fi
}

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
echo "🎉 Setup complete! You can now run: resize /path/to/image.jpg"
echo "👀 To specify a target aspect ratio, include the flag --WxH, such as "--9x16""
echo "ℹ️ Supported aspect ratios are 9x16, 4x5, 1x1, and 16x9"