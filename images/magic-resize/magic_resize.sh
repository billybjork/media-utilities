#!/bin/bash

# --- Configuration ---
# Default values (will be overridden)
DEFAULT_TARGET_RATIO_W=9
DEFAULT_TARGET_RATIO_H=16
SAMPLE_EDGE_THICKNESS=1      # Adjust as needed

# Ratio options: "WxH" format
declare -a RATIO_OPTIONS=("9x16" "4x5" "1x1" "16x9")

# --- Global Variables ---
# These will be set based on user choice or arguments
TARGET_RATIO_W=""
TARGET_RATIO_H=""
RATIO_SUFFIX="" # e.g., "_9x16"
INPUT_PATH=""

# --- Helper Functions ---

# Function to display usage instructions
usage() {
  local script_name
  script_name=$(basename "$0")
  echo "Usage: $script_name [--<WxH>] <input_file_or_directory>"
  echo ""
  echo "Processes the input image or all images (jpg, jpeg, png) in the input directory."
  echo "Resizes canvas to the specified aspect ratio, padding with solid colors sampled"
  echo "from the original image's relevant edges."
  echo ""
  echo "Arguments:"
  echo "  --<WxH>    (Optional) Specify the target aspect ratio directly."
  echo "             Supported ratios:"
  for ratio in "${RATIO_OPTIONS[@]}"; do
    echo "               --${ratio}"
  done
  echo "  <input_file_or_directory>"
  echo "             The image file or directory containing images to process."
  echo ""
  echo "If no --<WxH> argument is provided, you will be prompted to select a ratio."
  echo ""
  echo "Output:"
  echo "  Processed images are saved in the *same directory* as the originals,"
  echo "  with a suffix like '_9x16' appended to the filename (before the extension)."
  exit 1
}

# Function to parse ratio string (e.g., "9x16") and set global W/H/Suffix
set_ratio_vars() {
    local ratio_str=$1
    # Remove potential leading '--' if passed directly from arg
    ratio_str=${ratio_str#--}

    # Validate and split
    if [[ "$ratio_str" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        # Check if it's a supported ratio
        local supported=0
        for supported_ratio in "${RATIO_OPTIONS[@]}"; do
            if [[ "$ratio_str" == "$supported_ratio" ]]; then
                supported=1
                break
            fi
        done

        if [[ $supported -eq 1 ]]; then
            TARGET_RATIO_W="${BASH_REMATCH[1]}"
            TARGET_RATIO_H="${BASH_REMATCH[2]}"
            RATIO_SUFFIX="_${ratio_str}" # Use the string directly for the suffix
            # Validate W and H are positive
            if [[ "$TARGET_RATIO_W" -le 0 || "$TARGET_RATIO_H" -le 0 ]]; then
                 echo "Error: Invalid ratio components in '$ratio_str'. Must be positive integers." >&2
                 return 1
            fi
            # echo "Debug: Set ratio to W=$TARGET_RATIO_W, H=$TARGET_RATIO_H, Suffix=$RATIO_SUFFIX" # Debug line
            return 0 # Success
        else
            echo "Error: Unsupported aspect ratio '$ratio_str'." >&2
            echo "Supported ratios are: ${RATIO_OPTIONS[*]}" >&2
            return 1
        fi
    else
        echo "Error: Invalid ratio format '$ratio_str'. Expected format: WxH (e.g., 9x16)." >&2
        return 1
    fi
}

# Function to prompt user for aspect ratio
prompt_for_ratio() {
  echo "Please select the target aspect ratio:"
  local options_with_quit=("${RATIO_OPTIONS[@]}" "Quit")
  local choice
  # PS3 is the prompt string for select
  PS3="Enter number: "
  select choice in "${options_with_quit[@]}"; do
    case $choice in
      "Quit")
        echo "Operation cancelled by user."
        exit 0
        ;;
      *)
        # Check if choice is one of the valid ratios
        if [[ " ${RATIO_OPTIONS[*]} " =~ " ${choice} " ]]; then
           if set_ratio_vars "$choice"; then
               echo "Selected ratio: ${TARGET_RATIO_W}x${TARGET_RATIO_H}"
               break # Exit select loop
           else
               # set_ratio_vars prints error, just prompt again
               echo "Invalid selection."
           fi
        else
           echo "Invalid selection '$REPLY'. Please choose from the list."
        fi
        ;;
    esac
  done
}

# Function to process a single image file
process_image() {
  # Arguments passed implicitly: input_file
  # Global vars used: TARGET_RATIO_W, TARGET_RATIO_H, RATIO_SUFFIX
  local input_file="$1"

  # --- Safety check: Ensure ratio variables are set ---
  if [ -z "$TARGET_RATIO_W" ] || [ -z "$TARGET_RATIO_H" ] || [ -z "$RATIO_SUFFIX" ]; then
      echo "  Internal Error: Ratio variables not set before processing '$input_file'." >&2
      return 1 # Should not happen if main logic is correct
  fi

  local dir_name
  dir_name=$(dirname "$input_file")
  local base_name
  base_name=$(basename "$input_file")
  local extension="${base_name##*.}"
  local name_part="${base_name%.*}"

  # Construct the output filename using the dynamic suffix
  local output_file="${dir_name}/${name_part}${RATIO_SUFFIX}.${extension}"

  # Avoid processing file if it's already an output file *for this ratio*
  if [[ "$name_part" == *"${RATIO_SUFFIX}" ]]; then
       echo "  Skipping '$base_name' as it appears to be an already processed file for this ratio."
       return 0
  fi

  echo "Processing '$base_name' -> '${name_part}${RATIO_SUFFIX}.${extension}' (Target: ${TARGET_RATIO_W}x${TARGET_RATIO_H})"

  # Determine command based on availability (magick preferred)
  local magick_cmd="convert"
  local identify_cmd="identify"
  if command -v magick >/dev/null 2>&1; then
      magick_cmd="magick"
      identify_cmd="magick identify"
  fi

  # 1. Get original image dimensions
  local dimensions
  dimensions=$($identify_cmd -format "%w %h" "$input_file[0]" 2>/dev/null) # [0] for multi-frame gifs etc.

  if [ $? -ne 0 ] || [ -z "$dimensions" ]; then
    echo "  Error: Could not get dimensions for '$base_name'. Skipping."
    return 1
  fi
  local orig_w orig_h
  read -r orig_w orig_h <<<"$dimensions"

  if [ -z "$orig_w" ] || [ -z "$orig_h" ] || [ "$orig_w" -le 0 ] || [ "$orig_h" -le 0 ]; then
     echo "  Error: Invalid dimensions ($orig_w x $orig_h) for '$base_name'. Skipping."
     return 1
  fi

  # 2. Calculate target dimensions based on *SELECTED* ratio
  local target_w target_h
  local target_aspect_ratio image_aspect_ratio

  # Use bc for floating point comparison
  target_aspect_ratio=$(echo "scale=10; $TARGET_RATIO_W / $TARGET_RATIO_H" | bc -l)
  image_aspect_ratio=$(echo "scale=10; $orig_w / $orig_h" | bc -l)

  # Compare aspect ratios (allow small tolerance for floating point)
  local comparison
  comparison=$(echo "scale=10; diff = $image_aspect_ratio - $target_aspect_ratio; if (diff > -0.001 && diff < 0.001) 1 else 0" | bc -l)

  # If already the target ratio, just copy with new name
  if [ "$comparison" -eq 1 ]; then
      echo "  Image '$base_name' already matches ${TARGET_RATIO_W}:${TARGET_RATIO_H} ratio. Copying to '${name_part}${RATIO_SUFFIX}.${extension}'."
      cp "$input_file" "$output_file"
      if [ $? -ne 0 ]; then
          echo "  Error: Failed to copy '$input_file' to '$output_file'."
          return 1
      fi
      return 0
  fi

  local is_wider
  is_wider=$(echo "$image_aspect_ratio > $target_aspect_ratio" | bc -l)

  local pad_color1 pad_color2
  local extent_cmd

  # --- Calculate target canvas dimensions and padding colors ---
  if [ "$is_wider" -eq 1 ]; then
    # Image is wider than target ratio -> Fit to width, add padding top/bottom
    target_w=$orig_w
    target_h=$(printf "%.0f" "$(echo "scale=10; $orig_w * $TARGET_RATIO_H / $TARGET_RATIO_W" | bc -l)")

    # Sample top/bottom edges
    pad_color1=$($magick_cmd "$input_file[0]" -alpha off -crop "${orig_w}x${SAMPLE_EDGE_THICKNESS}+0+0" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)
    local bottom_y=$((orig_h - SAMPLE_EDGE_THICKNESS))
    [ $bottom_y -lt 0 ] && bottom_y=0
    pad_color2=$($magick_cmd "$input_file[0]" -alpha off -crop "${orig_w}x${SAMPLE_EDGE_THICKNESS}+0+${bottom_y}" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)

    # Build command for top/bottom padding
    local pad_y=$(( (target_h - orig_h) / 2 ))
    local bottom_rect_y=$(( pad_y + orig_h ))
    extent_cmd=( "$magick_cmd" \
        -size "${target_w}x${target_h}" "xc:$pad_color1" \
        -fill "$pad_color2" -draw "rectangle 0,${bottom_rect_y} ${target_w},${target_h}" \
        "$input_file[0]" -gravity center -compose over -composite \
    )

  else
    # Image is taller/narrower than target ratio -> Fit to height, add padding left/right
    target_h=$orig_h
    target_w=$(printf "%.0f" "$(echo "scale=10; $orig_h * $TARGET_RATIO_W / $TARGET_RATIO_H" | bc -l)")

    # Sample left/right edges
    pad_color1=$($magick_cmd "$input_file[0]" -alpha off -crop "${SAMPLE_EDGE_THICKNESS}x${orig_h}+0+0" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)
    local right_x=$((orig_w - SAMPLE_EDGE_THICKNESS))
    [ $right_x -lt 0 ] && right_x=0
    pad_color2=$($magick_cmd "$input_file[0]" -alpha off -crop "${SAMPLE_EDGE_THICKNESS}x${orig_h}+${right_x}+0" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)

    # Build command for left/right padding
    local pad_x=$(( (target_w - orig_w) / 2 ))
    local right_rect_x=$(( pad_x + orig_w ))
    extent_cmd=( "$magick_cmd" \
        -size "${target_w}x${target_h}" "xc:$pad_color1" \
        -fill "$pad_color2" -draw "rectangle ${right_rect_x},0 ${target_w},${target_h}" \
        "$input_file[0]" -gravity center -compose over -composite \
    )
  fi

  # Ensure target dimensions are at least 1x1
  target_w=$(( target_w > 0 ? target_w : 1 ))
  target_h=$(( target_h > 0 ? target_h : 1 ))

  # Check if colors were extracted successfully and set fallback if needed
  if [ -z "$pad_color1" ] || [ -z "$pad_color2" ]; then
      echo "  Warning: Could not extract edge colors for '$base_name'. Using black fallback."
      # Rebuild extent_cmd for simple black padding using -extent
      extent_cmd=( "$magick_cmd" "$input_file[0]" \
                   -gravity center -resize "${target_w}x${target_h}" \
                   -background black -extent "${target_w}x${target_h}" )
      # Note: When using extent, resize happens *before* extent.
      # The previous method created the canvas first, then composited.
      # If using extent, the resize geometry is different - it should resize
      # to fit *within* the final canvas, not necessarily fill one dimension.
      # Let's stick to the create canvas + composite method for fallback too for consistency.
      pad_color1="black"
      pad_color2="black" # Use black for both sides in fallback

      if [ "$is_wider" -eq 1 ]; then
          # Rebuild command for top/bottom padding with black
          local pad_y=$(( (target_h - orig_h) / 2 ))
          local bottom_rect_y=$(( pad_y + orig_h ))
          extent_cmd=( "$magick_cmd" \
              -size "${target_w}x${target_h}" "xc:$pad_color1" \
              -fill "$pad_color2" -draw "rectangle 0,${bottom_rect_y} ${target_w},${target_h}" \
              "$input_file[0]" -gravity center -compose over -composite \
          )
      else
          # Rebuild command for left/right padding with black
          local pad_x=$(( (target_w - orig_w) / 2 ))
          local right_rect_x=$(( pad_x + orig_w ))
          extent_cmd=( "$magick_cmd" \
              -size "${target_w}x${target_h}" "xc:$pad_color1" \
              -fill "$pad_color2" -draw "rectangle ${right_rect_x},0 ${target_w},${target_h}" \
              "$input_file[0]" -gravity center -compose over -composite \
          )
      fi
  fi

  # 3. Perform the conversion using ImageMagick
  local final_opts=()
  # Add JPG quality setting if needed
  if [[ "$extension" == "jpg" || "$extension" == "jpeg" ]]; then
      final_opts+=( -quality 92 )
      # If input could be PNG with alpha, ensure it's flattened for JPG
      # Add flattening options *before* the output filename in extent_cmd if needed
      # extent_cmd+=(-background white -alpha remove -alpha off) # Example
  fi

  # Execute the command
  "${extent_cmd[@]}" "${final_opts[@]}" "$output_file"

  if [ $? -eq 0 ]; then
    echo "  Successfully created '$output_file' (${target_w}x${target_h})"
  else
    echo "  Error: ImageMagick conversion failed for '$base_name'."
    # echo "  Failed command: ${extent_cmd[*]} ${final_opts[*]} \"$output_file\"" # Debug
    # Clean up potentially broken output file
    rm -f "$output_file"
    return 1
  fi
}

# --- Main Script Logic ---

# Check for required commands first
command -v identify >/dev/null 2>&1 || command -v magick >/dev/null 2>&1 || { echo >&2 "Error: ImageMagick ('identify' or 'magick') not found. Please install it."; exit 1; }
command -v convert >/dev/null 2>&1 || command -v magick >/dev/null 2>&1 || { echo >&2 "Error: ImageMagick ('convert' or 'magick') not found. Please install it."; exit 1; }
command -v bc >/dev/null 2>&1 || { echo >&2 "Error: 'bc' (calculator) not found. Please install it."; exit 1; }

# --- Argument Parsing ---
# Loop through arguments to find ratio flag and path
while (( "$#" )); do
  case "$1" in
    --*) # Potential ratio flag
      # Check if ratio is already set (meaning user provided flag twice or flag after path)
      if [ -n "$TARGET_RATIO_W" ]; then
          echo "Error: Ratio can only be specified once and must come before the path." >&2
          usage
      fi
      # Attempt to set ratio variables from the flag
      if ! set_ratio_vars "$1"; then
          # set_ratio_vars already printed error
          usage # Exit on invalid ratio flag
      fi
      shift # Consume the ratio argument
      ;;
    -h|--help)
      usage
      ;;
    *) # Not a flag starting with --, assume it's the input path
      # Check if path is already set (meaning user provided multiple paths)
      if [ -n "$INPUT_PATH" ]; then
          echo "Error: Only one input file or directory path can be specified." >&2
          usage
      fi
      INPUT_PATH="$1"
      shift # Consume the path argument
      ;;
  esac
done

# --- Validate Inputs ---

# 1. Check if Input Path was provided
if [ -z "$INPUT_PATH" ]; then
  echo "Error: No input file or directory specified." >&2
  usage
fi

# 2. Check if Ratio was set (either by flag or needs prompting)
if [ -z "$TARGET_RATIO_W" ]; then
    # No ratio flag was given, prompt the user
    prompt_for_ratio
    # Check again in case prompt failed or was cancelled (shouldn't happen with current prompt logic)
    if [ -z "$TARGET_RATIO_W" ]; then
        echo "Error: No aspect ratio selected." >&2
        exit 1;
    fi
fi

# 3. Check if Input Path exists
if [ ! -e "$INPUT_PATH" ]; then
    echo "Error: Input path '$INPUT_PATH' not found." >&2
    usage # Exit using usage function
fi

# --- Execute Processing ---

# Check if input is a file or directory
if [ -f "$INPUT_PATH" ]; then
  # Process single file
  process_image "$INPUT_PATH"
elif [ -d "$INPUT_PATH" ]; then
  # Process directory
  echo "Processing image files in directory '$INPUT_PATH' for ratio ${TARGET_RATIO_W}x${TARGET_RATIO_H}..."

  # Dynamically create the exclude pattern based on the selected ratio suffix
  exclude_pattern="*${RATIO_SUFFIX}.${extension}" # Note: extension var isn't set here, need suffix only
  exclude_pattern="*${RATIO_SUFFIX}.*"

  # Use find for safe handling of filenames with spaces/special chars
  # Exclude files that *already* end with the suffix for the *current* ratio
  find "$INPUT_PATH" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
    ! -name "$exclude_pattern" \
    -print0 | while IFS= read -r -d $'\0' file; do
      process_image "$file" # process_image uses the global ratio vars
  done
  echo "Directory processing complete."
else
  echo "Error: Input path '$INPUT_PATH' is not a valid file or directory." >&2
  usage
fi

echo "Script finished."
exit 0