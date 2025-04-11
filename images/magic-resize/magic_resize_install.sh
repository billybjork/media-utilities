#!/bin/bash

echo "🛠️  Setting up the 'resize' command..."

# --- Define ALL necessary variables FIRST ---
TOOL_NAME="smart_letterbox.sh"       # Actual script filename
TOOL_DIR="$HOME/.smart_letterbox"    # Directory to store the script
SCRIPT_PATH="$TOOL_DIR/$TOOL_NAME"   # Full path to the script
ALIAS_TARGET_PATH="$SCRIPT_PATH"     # What the alias should point to
ALIAS_NAME="resize"                  # The name of the alias command
SCRIPT_URL="https://raw.githubusercontent.com/billybjork/media-utilities/main/images/magic-resize/magic_resize.sh"

# --- Step 1: Set up script location and download ---
echo "Creating tool directory: $TOOL_DIR"
mkdir -p "$TOOL_DIR" || { echo "❌ Failed to create directory '$TOOL_DIR'."; exit 1; }

echo "Downloading script..."
# Download script using curl
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH" || {
  echo "❌ Failed to download script from '$SCRIPT_URL'."
  echo "   Please check the URL and your internet connection."
  exit 1;
}

# Make the downloaded script executable
chmod +x "$SCRIPT_PATH" || {
  echo "❌ Failed to make script executable at '$SCRIPT_PATH'."
  exit 1;
}
echo "✅ Script downloaded and made executable."


# --- Step 2: Add alias to shell config ---
# Define the alias command string using the variables defined above
ALIAS_COMMAND="alias $ALIAS_NAME='$ALIAS_TARGET_PATH'"
CONFIG_CHANGED=0

# Function to add alias if not present
add_alias() {
    local rc_file="$1"
    local shell_name="$2"
    if [ -f "$rc_file" ]; then
      # Check specifically for the CORRECT alias command string
      if ! grep -Fxq "$ALIAS_COMMAND" "$rc_file"; then
        # Remove any OLD incorrect aliases or previous versions first
        # This targets lines starting with 'alias resize=' regardless of path for simplicity
        # Use sed -i.bak for macOS compatibility
        sed -i.bak "/^alias ${ALIAS_NAME}=/d" "$rc_file" &>/dev/null

        echo "" >> "$rc_file" # Add newline for separation
        echo "# Alias for smart image resize tool ($TOOL_NAME)" >> "$rc_file"
        echo "$ALIAS_COMMAND" >> "$rc_file" # Add the CORRECT alias
        echo "✅ Alias '$ALIAS_NAME' added/corrected in $rc_file"
        CONFIG_CHANGED=1
      else
        # If the correct alias is already there, we don't need to do anything.
        echo "✅ Correct alias '$ALIAS_NAME' already exists in $rc_file"
      fi
    else
        echo "ℹ️ $rc_file not found (normal if you primarily use a different shell than $shell_name)."
    fi
}

# Call the function for relevant shell configuration files
add_alias "$HOME/.zshrc" "Zsh"
add_alias "$HOME/.bashrc" "Bash"
if [ ! -f "$HOME/.bashrc" ] && [ -f "$HOME/.bash_profile" ]; then
    add_alias "$HOME/.bash_profile" "Bash Profile"
fi


# --- Step 3: Check and Install ImageMagick via Homebrew ---
echo "Checking for ImageMagick..."
if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "⚠️ ImageMagick not found. This tool requires ImageMagick to function."
  
  # Check for Homebrew command
  if ! command -v brew >/dev/null 2>&1; then
    echo "🍺 Homebrew package manager not found. Attempting to install Homebrew..."
    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      echo "❌ Failed to install Homebrew automatically."
      echo "   Please visit https://brew.sh for manual installation instructions."
      echo "   You will then need to run 'brew install imagemagick' manually."
      exit 1; # Exit if Homebrew install fails
    }
     # Add Homebrew to PATH for the current script execution if possible
     if [[ "$(uname -m)" == "arm64" ]]; then # Apple Silicon
       export PATH="/opt/homebrew/bin:$PATH"
     else # Intel
       export PATH="/usr/local/bin:$PATH"
     fi
     echo "✅ Homebrew installed."
  else
     echo "🍺 Homebrew found."
  fi

  # Now install ImageMagick using Homebrew
  echo "📦 Installing ImageMagick via Homebrew..."
  brew install imagemagick || {
    echo "❌ Failed to install ImageMagick using Homebrew."
    echo "   You may need to run 'brew update' first, or check 'brew doctor'."
    echo "   Try running 'brew install imagemagick' manually."
    exit 1; # Exit if ImageMagick install fails
  }
  echo "✅ ImageMagick installed via Homebrew!"
else
  echo "✅ ImageMagick is already installed."
fi


# --- Step 4: Finalize ---
echo ""
echo "🎉 Setup complete!"
if [ "$CONFIG_CHANGED" -eq 1 ]; then
    echo "   IMPORTANT: Alias was added/updated. To activate the '$ALIAS_NAME' command,"
    echo "   please CLOSE and REOPEN your terminal window, or run *one* of these:"
    [ -f "$HOME/.zshrc" ] && echo "     source ~/.zshrc"
    [ -f "$HOME/.bashrc" ] && echo "     source ~/.bashrc"
    [ ! -f "$HOME/.bashrc" ] && [ -f "$HOME/.bash_profile" ] && echo "     source ~/.bash_profile"
else
     echo "   Alias status checked. If the command isn't working, try restarting your terminal"
     echo "   or ensure the correct alias exists in your shell config file (~/.zshrc or ~/.bashrc)."
fi
echo "   You can then run the command from any directory, e.g.:"
echo "     $ALIAS_NAME my_image.jpg"
echo "     $ALIAS_NAME --1x1 my_folder/"

exit 0