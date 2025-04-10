import cv2
import pytesseract
import argparse
import os

def extract_text_from_video(video_path, output_path, sample_interval_sec=1):
    # Open the video file
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Error opening video file: {video_path}")
        return

    # Get video FPS to calculate frame intervals
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_interval = int(fps * sample_interval_sec)
    frame_count = 0

    with open(output_path, 'w', encoding='utf-8') as f:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            # Process the frame based on sampling interval
            if frame_count % frame_interval == 0:
                # Convert frame to grayscale (improves OCR accuracy)
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                
                # Extract text from the grayscale image
                text = pytesseract.image_to_string(gray)
                if text.strip():
                    # Write the frame number and timestamp along with the extracted text
                    f.write(f"Frame {frame_count} (Time: {frame_count/fps:.2f} sec):\n")
                    f.write(text)
                    f.write("\n" + "="*50 + "\n")
            frame_count += 1

    cap.release()
    print(f"Text extraction complete. Output saved to {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract text overlays from a video using OCR.")
    parser.add_argument("video_file", help="Path to the input video file (e.g., file.mp4)")
    parser.add_argument("--sample_interval", type=float, default=1,
                        help="Sampling interval in seconds (default is 1 second)")
    args = parser.parse_args()

    # Default the output file to the same name and path as the video file with a .txt extension
    output_file = os.path.splitext(args.video_file)[0] + ".txt"

    if not os.path.exists(args.video_file):
        print(f"Video file {args.video_file} does not exist.")
        exit(1)

    extract_text_from_video(args.video_file, output_file, args.sample_interval)