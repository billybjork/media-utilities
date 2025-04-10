import os
import subprocess
import argparse
import whisper
import sys
import time

# --- Configuration ---
SUPPORTED_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".wmv", ".flv", ".webm", ".m4v"} # Add more if needed
DEFAULT_OUTPUT_FILENAME = "video_transcriptions.txt"
DEFAULT_WHISPER_MODEL = "base" # Options: tiny, base, small, medium, large (larger = more accurate, slower, more VRAM)
TEMP_AUDIO_FILENAME = "_temp_audio.wav" # Temporary file for extracted audio

# --- Functions ---

def is_video_file(filename):
    """Checks if a filename has a supported video extension."""
    _, ext = os.path.splitext(filename)
    return ext.lower() in SUPPORTED_EXTENSIONS

def extract_audio(video_path, audio_path):
    """
    Extracts audio from a video file using ffmpeg.
    Returns True on success, False on failure.
    """
    print(f"   Extracting audio from '{os.path.basename(video_path)}'...")
    command = [
        'ffmpeg',
        '-i', video_path,      # Input file
        '-y',                  # Overwrite output file without asking
        '-vn',                 # Disable video recording
        '-acodec', 'pcm_s16le',# Audio codec: WAV format (signed 16-bit PCM)
        '-ar', '16000',        # Audio sample rate: 16kHz (recommended for Whisper)
        '-ac', '1',            # Audio channels: 1 (mono)
        audio_path             # Output file
    ]
    try:
        # Use subprocess.run for better control and error handling
        # stderr=subprocess.PIPE and stdout=subprocess.PIPE hides ffmpeg's output unless there's an error
        # Use stderr=subprocess.DEVNULL and stdout=subprocess.DEVNULL to completely silence ffmpeg
        result = subprocess.run(command, check=True, text=True, capture_output=True)
                                #stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) # Uncomment to silence ffmpeg
        print(f"   Audio extracted successfully to '{os.path.basename(audio_path)}'.")
        return True
    except FileNotFoundError:
        print("\nError: 'ffmpeg' command not found. Please ensure ffmpeg is installed and in your system's PATH.", file=sys.stderr)
        return False
    except subprocess.CalledProcessError as e:
        print(f"\nError during audio extraction for '{os.path.basename(video_path)}':", file=sys.stderr)
        print(f"  Command: {' '.join(e.cmd)}", file=sys.stderr)
        print(f"  Return Code: {e.returncode}", file=sys.stderr)
        print(f"  Stderr: {e.stderr}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"\nAn unexpected error occurred during audio extraction for '{os.path.basename(video_path)}': {e}", file=sys.stderr)
        return False

def transcribe_audio(audio_path, model):
    """
    Transcribes audio using the loaded Whisper model.
    Returns the transcription text or None on failure.
    """
    print(f"   Transcribing '{os.path.basename(audio_path)}'...")
    try:
        start_time = time.time()
        # Load the model inside the function if you want per-file model loading (less efficient)
        # model = whisper.load_model(whisper_model_name)
        result = model.transcribe(audio_path, fp16=False) # fp16=False for CPU, can be True for GPU
        end_time = time.time()
        duration = end_time - start_time
        print(f"   Transcription complete ({duration:.2f}s).")
        return result['text']
    except Exception as e:
        print(f"\nError during transcription for '{os.path.basename(audio_path)}': {e}", file=sys.stderr)
        return None

def cleanup_temp_file(filepath):
    """Deletes a file if it exists."""
    if os.path.exists(filepath):
        try:
            os.remove(filepath)
            # print(f"   Cleaned up temporary file: {os.path.basename(filepath)}")
        except OSError as e:
            print(f"\nWarning: Could not delete temporary file '{os.path.basename(filepath)}': {e}", file=sys.stderr)

# --- Main Execution ---

def main():
    parser = argparse.ArgumentParser(description="Transcribe audio from all video files in a directory using Whisper.")
    parser.add_argument("input_dir", help="Path to the directory containing video files.")
    parser.add_argument("-o", "--output", default=DEFAULT_OUTPUT_FILENAME,
                        help=f"Path to the output text file (default: {DEFAULT_OUTPUT_FILENAME})")
    parser.add_argument("-m", "--model", default=DEFAULT_WHISPER_MODEL,
                        choices=["tiny", "base", "small", "medium", "large"],
                        help=f"Whisper model size to use (default: {DEFAULT_WHISPER_MODEL})")
    parser.add_argument("--force-cpu", action="store_true",
                        help="Force Whisper to use CPU even if GPU is available.")

    args = parser.parse_args()

    input_directory = args.input_dir
    output_filepath = args.output
    whisper_model_name = args.model

    if not os.path.isdir(input_directory):
        print(f"Error: Input directory not found: {input_directory}", file=sys.stderr)
        sys.exit(1)

    # Find video files
    video_files = [
        f for f in os.listdir(input_directory)
        if os.path.isfile(os.path.join(input_directory, f)) and is_video_file(f)
    ]

    if not video_files:
        print(f"No video files with supported extensions found in {input_directory}")
        sys.exit(0)

    print(f"Found {len(video_files)} video file(s) in '{input_directory}'.")
    print(f"Using Whisper model: '{whisper_model_name}'")
    print(f"Output will be saved to: '{output_filepath}'")

    # Load Whisper model (do this once)
    print("Loading Whisper model...")
    try:
        if args.force_cpu:
            print("(Forcing CPU usage)")
            model = whisper.load_model(whisper_model_name, device="cpu")
        else:
            # Whisper automatically detects GPU if available and PyTorch is correctly installed
            model = whisper.load_model(whisper_model_name)
            # Check device being used (optional)
            # try:
            #     import torch
            #     device = "GPU (CUDA)" if torch.cuda.is_available() else "CPU"
            #     print(f"(Using device: {device})")
            # except ImportError:
            #     print("(Using device: CPU - PyTorch not found or no CUDA)")

    except Exception as e:
        print(f"\nError loading Whisper model '{whisper_model_name}': {e}", file=sys.stderr)
        print("Ensure the model name is correct and you have enough memory/VRAM.", file=sys.stderr)
        sys.exit(1)
    print("Model loaded successfully.")

    # Process each video file
    successful_transcriptions = 0
    with open(output_filepath, 'w', encoding='utf-8') as outfile:
        for i, filename in enumerate(video_files):
            print(f"\nProcessing file {i+1}/{len(video_files)}: {filename}")
            video_path = os.path.join(input_directory, filename)
            # Define temp audio path relative to input directory or a dedicated temp dir
            temp_audio_path = os.path.join(input_directory, TEMP_AUDIO_FILENAME)

            transcription = None # Reset for each file

            # 1. Extract Audio
            if extract_audio(video_path, temp_audio_path):
                # 2. Transcribe Audio
                transcription = transcribe_audio(temp_audio_path, model)

            # 3. Write to Output File
            if transcription is not None:
                outfile.write(f"--- Transcription for: {filename} ---\n")
                outfile.write(transcription.strip()) # Remove leading/trailing whitespace
                outfile.write("\n\n") # Add blank lines for separation
                successful_transcriptions += 1
            else:
                print(f"   Skipping transcription for '{filename}' due to previous errors.")
                outfile.write(f"--- Transcription FAILED for: {filename} ---\n\n") # Log failure

            # 4. Cleanup Temporary Audio File
            cleanup_temp_file(temp_audio_path)

    print("\n--------------------")
    print("Processing Complete.")
    print(f"Successfully transcribed {successful_transcriptions} out of {len(video_files)} video files.")
    print(f"Results saved to: {output_filepath}")
    print("--------------------")

if __name__ == "__main__":
    main()