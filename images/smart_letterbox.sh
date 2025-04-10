#!/bin/bash

# --- Configuration ---
TARGET_RATIO_W=9             # Target aspect ratio width component
TARGET_RATIO_H=16            # Target aspect ratio height component
SAMPLE_EDGE_THICKNESS=1      # How many pixels thick the edge sample should be (1 is usually fine)
FILENAME_SUFFIX="_resized"   # Suffix to add to the output filename

# --- Helper Functions ---

# Function to display usage instructions
usage() {
  echo "Usage: $0 <input_file_or_directory>"
  echo "  Processes the input image or all images (jpg, jpeg, png) in the input directory."
  echo "  Resizes canvas to 9:16 aspect ratio, padding with solid colors sampled"
  echo "  from the original image's relevant edges."
  echo "  Output is saved in the *same directory* as the original, with '${FILENAME_SUFFIX}'"
  echo "  appended to the filename (before the extension)."
  exit 1
}

# Function to process a single image file
process_image() {
  local input_file="$1"
  local dir_name
  dir_name=$(dirname "$input_file")
  local base_name
  base_name=$(basename "$input_file")
  local extension="${base_name##*.}"
  local name_part="${base_name%.*}"

  # Construct the output filename in the same directory
  local output_file="${dir_name}/${name_part}${FILENAME_SUFFIX}.${extension}"

  # Avoid processing if the output file is the same as input (e.g., script run twice)
  if [[ "$input_file" == "$output_file" ]]; then
      echo "  Skipping '$input_file' as it already has the suffix '${FILENAME_SUFFIX}'."
      return 0
  fi
   # Avoid processing file if it's already an output file from a previous run
  if [[ "$name_part" == *"${FILENAME_SUFFIX}" ]]; then
       echo "  Skipping '$input_file' as it appears to be an already processed file."
       return 0
  fi

  echo "Processing '$input_file' -> '$output_file'"

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
    echo "  Error: Could not get dimensions for '$input_file'. Skipping."
    return 1
  fi
  local orig_w orig_h
  read -r orig_w orig_h <<<"$dimensions"

  if [ -z "$orig_w" ] || [ -z "$orig_h" ] || [ "$orig_w" -le 0 ] || [ "$orig_h" -le 0 ]; then
     echo "  Error: Invalid dimensions ($orig_w x $orig_h) for '$input_file'. Skipping."
     return 1
  fi

  # 2. Calculate target 9:16 dimensions while containing the original
  local target_w target_h
  local target_aspect_ratio image_aspect_ratio

  # Use bc for floating point comparison
  target_aspect_ratio=$(echo "scale=10; $TARGET_RATIO_W / $TARGET_RATIO_H" | bc -l)
  image_aspect_ratio=$(echo "scale=10; $orig_w / $orig_h" | bc -l)

  # Compare aspect ratios (1=true, 0=false)
  local comparison
  comparison=$(echo "$image_aspect_ratio == $target_aspect_ratio" | bc -l)

  # If already the target ratio, just copy with new name (optional, could skip entirely)
  if [ "$comparison" -eq 1 ]; then
      echo "  Image '$base_name' is already ${TARGET_RATIO_W}:${TARGET_RATIO_H}. Copying to '$output_file'."
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

  if [ "$is_wider" -eq 1 ]; then
    # Image is wider than 9:16 (e.g., landscape) -> Fit to width, add padding top/bottom
    target_w=$orig_w
    target_h=$(printf "%.0f" "$(echo "scale=10; $orig_w * $TARGET_RATIO_H / $TARGET_RATIO_W" | bc -l)")

    # Sample top edge color
    pad_color1=$($magick_cmd "$input_file[0]" -alpha off -crop "${orig_w}x${SAMPLE_EDGE_THICKNESS}+0+0" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)
    # Sample bottom edge color
    local bottom_y=$((orig_h - SAMPLE_EDGE_THICKNESS))
    [ $bottom_y -lt 0 ] && bottom_y=0 # Ensure not negative for thin images
    pad_color2=$($magick_cmd "$input_file[0]" -alpha off -crop "${orig_w}x${SAMPLE_EDGE_THICKNESS}+0+${bottom_y}" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)

    # echo "  Detected wider image. Padding top/bottom." # Less verbose
    # echo "  Top color: $pad_color1, Bottom color: $pad_color2"

    # Create background: base color (top), draw rect for bottom, composite original
    local pad_y=$(( (target_h - orig_h) / 2 )) # Integer division is fine here
    # Calculate bottom rect placement carefully - should start *after* the centered image space
    local bottom_rect_y=$(( pad_y + orig_h ))
    # Ensure bottom rectangle doesn't overdraw if padding is odd
    if (( (target_h - orig_h) % 2 != 0 )); then
        bottom_rect_y=$(( bottom_rect_y )) # Adjust if needed, but usually gravity center handles this implicitly
    fi

    extent_cmd=( "$magick_cmd" \
        -size "${target_w}x${target_h}" "xc:$pad_color1" \
        -fill "$pad_color2" -draw "rectangle 0,${bottom_rect_y} ${target_w},${target_h}" \
        "$input_file[0]" -gravity center -compose over -composite \
    )

  else
    # Image is taller/narrower than 9:16 (e.g., portrait/square) -> Fit to height, add padding left/right
    target_h=$orig_h
    target_w=$(printf "%.0f" "$(echo "scale=10; $orig_h * $TARGET_RATIO_W / $TARGET_RATIO_H" | bc -l)")

    # Sample left edge color
    pad_color1=$($magick_cmd "$input_file[0]" -alpha off -crop "${SAMPLE_EDGE_THICKNESS}x${orig_h}+0+0" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)
    # Sample right edge color
    local right_x=$((orig_w - SAMPLE_EDGE_THICKNESS))
    [ $right_x -lt 0 ] && right_x=0 # Ensure not negative
    pad_color2=$($magick_cmd "$input_file[0]" -alpha off -crop "${SAMPLE_EDGE_THICKNESS}x${orig_h}+${right_x}+0" +repage -resize 1x1! -format '%[pixel:p{0,0}]' info: 2>/dev/null)

    # echo "  Detected taller/narrower image. Padding left/right." # Less verbose
    # echo "  Left color: $pad_color1, Right color: $pad_color2"

    # Create background: base color (left), draw rect for right, composite original
    local pad_x=$(( (target_w - orig_w) / 2 ))
    # Calculate right rect placement carefully
    local right_rect_x=$(( pad_x + orig_w ))
    # Ensure right rectangle doesn't overdraw if padding is odd
    if (( (target_w - orig_w) % 2 != 0 )); then
        right_rect_x=$(( right_rect_x ))
    fi

    extent_cmd=( "$magick_cmd" \
        -size "${target_w}x${target_h}" "xc:$pad_color1" \
        -fill "$pad_color2" -draw "rectangle ${right_rect_x},0 ${target_w},${target_h}" \
        "$input_file[0]" -gravity center -compose over -composite \
    )
  fi

  # Ensure dimensions are at least 1x1
  target_w=$(( target_w > 0 ? target_w : 1 ))
  target_h=$(( target_h > 0 ? target_h : 1 ))

  # Check if colors were extracted successfully
  if [ -z "$pad_color1" ] || [ -z "$pad_color2" ]; then
      echo "  Warning: Could not extract edge colors for '$base_name'. Using black fallback."
      # Fallback: Use simple extent with black background
      extent_cmd=( "$magick_cmd" "$input_file[0]" -resize "${target_w}x${target_h}" \
          -background black -gravity center -extent "${target_w}x${target_h}" )
      # Add alpha channel handling for fallback if needed, e.g., for PNGs
      # Ensure output format supports transparency if input had it and black is used
      # if [[ "$extension" == "png" ]]; then
      #     extent_cmd+=( -alpha set )
      # fi
  fi

  # 3. Perform the conversion using ImageMagick
  # Add -alpha off before final output to ensure solid background for formats like JPG
  # Add -quality for JPG output
  local final_opts=()
  if [[ "$extension" == "jpg" || "$extension" == "jpeg" ]]; then
      final_opts=( -quality 92 ) # Adjust quality as needed
  fi


  # Execute the command
  "${extent_cmd[@]}" "${final_opts[@]}" "$output_file"


  if [ $? -eq 0 ]; then
    echo "  Successfully created '$output_file' (${target_w}x${target_h})"
  else
    echo "  Error: ImageMagick conversion failed for '$input_file'."
    # echo "  Failed command: ${extent_cmd[*]} ${final_opts[*]} \"$output_file\"" # Uncomment for debug
    # Clean up potentially broken output file
    rm -f "$output_file"
    return 1
  fi
}

# --- Main Script ---

# Check for required commands
command -v identify >/dev/null 2>&1 || command -v magick >/dev/null 2>&1 || { echo >&2 "Error: ImageMagick ('identify' or 'magick') not found. Please install it."; exit 1; }
command -v convert >/dev/null 2>&1 || command -v magick >/dev/null 2>&1 || { echo >&2 "Error: ImageMagick ('convert' or 'magick') not found. Please install it."; exit 1; }
command -v bc >/dev/null 2>&1 || { echo >&2 "Error: 'bc' (calculator) not found. Please install it."; exit 1; }

# Check for input argument
if [ -z "$1" ]; then
  echo "Error: No input file or directory specified."
  usage
fi

INPUT_PATH="$1"

# Removed output directory creation logic

# Check if input is a file or directory
if [ -f "$INPUT_PATH" ]; then
  # Process single file
  process_image "$INPUT_PATH"
elif [ -d "$INPUT_PATH" ]; then
  # Process directory
  echo "Processing files in directory '$INPUT_PATH'..."
  shopt -s extglob # Enable extended globbing for the exclusion pattern

  # Use find for safe handling of filenames with spaces/special chars
  # Exclude files that *already* end with the suffix
  find "$INPUT_PATH" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
    ! -name "*${FILENAME_SUFFIX}.*" \
    -print0 | while IFS= read -r -d $'\0' file; do
      process_image "$file"
  done

  shopt -u extglob # Disable extended globbing
  echo "Directory processing complete."
else
  echo "Error: Input path '$INPUT_PATH' is not a valid file or directory."
  usage
fi

echo "Script finished."
exit 0