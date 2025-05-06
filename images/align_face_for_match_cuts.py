#!/usr/bin/env python3
import os
import cv2
import math
import argparse
import numpy as np
import face_recognition
from PIL import Image, ImageDraw
import time

"""
Align Face for Match Cuts Script
=====================================================

Overview:
---------
This script processes a folder of images containing a specific person's face.
It aligns the face consistently across all images based on rotation, scale,
and position, preparing them for seamless match-cut video sequences.

The core alignment method uses OpenCV's affine transformation capabilities.
It identifies key facial landmarks (eye centers, nose tip) in each source image
and calculates the transformation matrix needed to map these points to predefined
target locations on a final, large canvas. This ensures that:
  - The line connecting the eyes is horizontal.
  - The distance between the eyes matches a specified target width.
  - The midpoint between the eyes is centered on the final canvas.

The script outputs images onto a fixed canvas size (12228x6912 pixels).
It generates an alpha mask based on the original image's footprint to ensure
proper transparency for PNG output and correct compositing for JPG output,
preserving all original pixels within the transformed area.

Features:
---------
- Face detection and matching against reference image(s).
- Alignment via direct affine transformation mapping (eyes + nose tip).
- Consistent eye distance scaling (`target_face_width`).
- Consistent face centering on the output canvas.
- Horizontal eye alignment.
- Output to a large, fixed canvas (12228x6912).
- Choice of output format:
    - PNG with transparency outside the warped image area.
    - JPG composited onto a white background.
- Optional use of the more accurate (but slower) CNN face detector.
- Optional debug mode to visualize the target eye alignment on output images.

Arguments:
----------
--input_folder      (required) Folder containing input images.
--output_folder     (required) Folder where the processed images will be saved
                    (in a '_processed' subdirectory).
--reference         (required) Path to a reference image, comma-separated list of
                    image paths, or a folder containing reference images for
                    identifying the target person.
--target_face_width (optional) Desired final distance between the eye centers in
                    pixels (default: 200). Controls the scale of the face.
--use_cnn           (optional flag) Use the CNN model for face detection instead
                    of the default HOG model (slower, potentially more accurate).
--jpg               (optional flag) Output in JPG format with a white background.
                    Default is PNG format with transparency.
--testing           (optional flag) Process only the first 10 images found in
                    the input folder for quick testing.
--debug_draw        (optional flag) Save additional debug images (in a
                    '_debug_affine' subdirectory) showing the final warped
                    image with the target eye locations marked.

Notes:
------
- Landmark detection relies on the `face_recognition` library. Accuracy of
  alignment depends on the accuracy of detected landmarks. Using `--use_cnn`
  is recommended for best results if processing time allows.
- The script requires the 'nose_bridge' landmark group for the affine transform.
- Because the image is warped directly onto the final large canvas, parts of the
  original image far from the centered face (e.g., shoulders, background) may
  be cropped if they fall outside the canvas boundaries after transformation.
"""

# --- Helper Functions ---

def load_reference_encodings(ref_path):
    """
    Loads face encodings from reference image(s) or a folder.

    Args:
        ref_path (str): Path to a single image, comma-separated list of images,
                        or a directory containing reference images.

    Returns:
        list: A list of face encoding arrays (numpy.ndarray). Returns an
              empty list if no valid references or faces are found.
    """
    if os.path.isdir(ref_path):
        # Load from directory
        ref_paths = [os.path.join(ref_path, f) for f in os.listdir(ref_path)
                     if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
    else:
        # Load from single file or comma-separated list
        ref_paths = [p.strip() for p in ref_path.split(",") if os.path.isfile(p.strip())]

    if not ref_paths:
        print(f"Error: No valid image files found for reference path: {ref_path}")
        return []

    encodings = []
    print(f"Loading reference faces from: {', '.join([os.path.basename(p) for p in ref_paths])}")
    for r in ref_paths:
        try:
            image = face_recognition.load_image_file(r)
            # Use default HOG model for reference encoding (faster)
            face_encs = face_recognition.face_encodings(image)
            if face_encs:
                 encodings.append(face_encs[0]) # Assuming one face per reference image
                 print(f"  Loaded encoding from {os.path.basename(r)}")
            else:
                 print(f"Warning: No face found in reference image {r}")
        except Exception as e:
             print(f"Error loading reference image {r}: {e}")

    if not encodings:
        print("Warning: No face encodings could be loaded from reference images.")
    return encodings

def get_target_face(image, reference_encodings, use_cnn=False, tolerance=0.6):
    """
    Detects faces in an image and selects the one best matching the reference encodings.

    Args:
        image (numpy.ndarray): Image array (RGB format from face_recognition.load_image_file).
        reference_encodings (list): List of known face encodings.
        use_cnn (bool): Whether to use the CNN model for detection.
        tolerance (float): How much distance between faces to consider it a match.
                           Lower is stricter. 0.6 is typical.

    Returns:
        tuple: (best_face_location, best_landmarks, best_distance)
               Returns (None, None, None) if no suitable face is found.
               'best_landmarks' is a dictionary of landmark points.
    """
    start_time = time.time()
    model = "cnn" if use_cnn else "hog"
    face_locations = face_recognition.face_locations(image, model=model)

    if not face_locations:
        return None, None, None # No faces detected

    face_encodings = face_recognition.face_encodings(image, face_locations)

    best_face_location = None
    best_landmarks = None
    best_distance = float('inf')

    if not reference_encodings:
        # If no references provided, default to the first detected face
        print("  No reference encodings provided, using the first detected face.")
        best_face_location = face_locations[0]
        best_distance = 0 # Assign arbitrary distance
    else:
        # Find the face with the minimum distance to any reference encoding
        for location, encoding in zip(face_locations, face_encodings):
            distances = face_recognition.face_distance(reference_encodings, encoding)
            min_distance = np.min(distances)
            # Check if this face is a better match than current best and meets tolerance
            if min_distance < best_distance and min_distance <= tolerance:
                best_distance = min_distance
                best_face_location = location

    if best_face_location is None:
        # No face matched the references within the tolerance
        if reference_encodings:
             print(f"  No face matched reference with tolerance {tolerance}. Smallest dist: {best_distance if best_distance != float('inf') else 'N/A'}")
        return None, None, None

    # Get landmarks for the selected face
    # Use the 'large' model for potentially more accurate/stable landmarks needed for affine transform
    landmarks_list = face_recognition.face_landmarks(image, [best_face_location], model='large')
    if landmarks_list:
        best_landmarks = landmarks_list[0]

    return best_face_location, best_landmarks, best_distance

# --- Main Processing Function ---

def process_image_direct_affine(image_path, reference_encodings, target_face_width,
                                final_canvas_size, anchor_point, use_cnn=False):
    """
    Detects the target face, calculates the affine transform to align it,
    and warps the image and an alpha mask directly onto the final canvas dimensions.

    Args:
        image_path (str): Path to the input image.
        reference_encodings (list): List of reference face encodings.
        target_face_width (int): Desired distance between eyes in the output.
        final_canvas_size (tuple): (width, height) of the output canvas.
        anchor_point (tuple): (x, y) coordinates on the canvas where the
                              face center (eye midpoint) should be placed.
        use_cnn (bool): Whether to use the CNN face detector.

    Returns:
        tuple: (warped_image_cv, warped_mask, status, dest_left_eye, dest_right_eye)
               - warped_image_cv: Warped image as an OpenCV BGR numpy array.
               - warped_mask: Warped alpha mask as a grayscale numpy array.
               - status: 'success', 'fallback_landmarks', 'error', etc.
               - dest_left_eye, dest_right_eye: Target coordinates for eyes (for debug).
               Returns (None, None, status, None, None) on failure.
    """
    final_canvas_width, final_canvas_height = final_canvas_size
    warped_mask = None # Initialize mask return value

    # --- Load Image ---
    try:
        image_rgb = face_recognition.load_image_file(image_path)
        img_h, img_w, _ = image_rgb.shape
        image_bgr = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR) # OpenCV uses BGR
    except Exception as e:
        print(f"Error loading image {image_path}: {e}")
        return None, None, 'error_load', None, None

    # --- Find Face and Landmarks ---
    face_location, landmarks, distance = get_target_face(image_rgb, reference_encodings, use_cnn)

    # Check if necessary landmarks were found
    if (face_location is None or landmarks is None or
            not landmarks.get('left_eye') or not landmarks.get('right_eye') or
            not landmarks.get('nose_bridge')): # nose_bridge is needed for the 3rd point
        print(f"  -> No matching face or required landmarks (eyes, nose_bridge) found in {os.path.basename(image_path)}. Skipping.")
        return None, None, 'fallback_landmarks', None, None

    # --- Define Source Points (from detected landmarks) ---
    try:
        left_eye_pts = np.array(landmarks['left_eye'])
        right_eye_pts = np.array(landmarks['right_eye'])
        nose_pts = np.array(landmarks['nose_bridge']) # Use nose_bridge group
        # Calculate average center for eyes
        orig_left_center = left_eye_pts.mean(axis=0)
        orig_right_center = right_eye_pts.mean(axis=0)
        # Use the bottom point of the nose bridge as the third stable point
        orig_nose_tip = nose_pts[-1]
        # Define the 3 source points for the affine transform
        pts_src = np.float32([orig_left_center, orig_right_center, orig_nose_tip])
    except Exception as e:
        print(f"  Error processing landmarks for {os.path.basename(image_path)}: {e}")
        return None, None, 'error_landmarks', None, None

    # --- Define Destination Points (on the final canvas) ---
    cx, cy = anchor_point # Center of the canvas
    # Target eye positions: centered horizontally, target_face_width apart, same Y coordinate
    dest_left_eye = np.float32([cx - target_face_width / 2.0, cy])
    dest_right_eye = np.float32([cx + target_face_width / 2.0, cy])

    # Calculate the target nose tip position to maintain geometric proportions
    # 1. Find midpoint between eyes in source and destination
    eye_midpoint_src = (orig_left_center + orig_right_center) / 2.0
    eye_midpoint_dst = anchor_point # By definition, the target eye midpoint is the anchor

    # 2. Find vector between eyes in source to determine original scale and angle
    vec_eyes_src = orig_right_center - orig_left_center
    dist_eyes_src = np.linalg.norm(vec_eyes_src)
    if dist_eyes_src < 1e-6: # Avoid division by zero
        print(f"  Warning: Zero source eye distance in {os.path.basename(image_path)}. Skipping.")
        return None, None, 'error_geometry', None, None

    # 3. Calculate the implied scale and rotation needed to map source eyes to dest eyes
    scale = target_face_width / dist_eyes_src
    angle_rad = math.atan2(vec_eyes_src[1], vec_eyes_src[0]) # Angle of the source eye line

    # 4. Get vector from source eye midpoint to source nose tip
    vec_mid_to_nose_src = orig_nose_tip - eye_midpoint_src

    # 5. Rotate this vector by the *negative* of the source eye angle to align it relative to a horizontal baseline
    cos_a = math.cos(-angle_rad)
    sin_a = math.sin(-angle_rad)
    vec_rotated_nose = np.array([
        vec_mid_to_nose_src[0] * cos_a - vec_mid_to_nose_src[1] * sin_a,
        vec_mid_to_nose_src[0] * sin_a + vec_mid_to_nose_src[1] * cos_a
    ])

    # 6. Scale the rotated vector by the calculated scale factor
    vec_nose_dst = vec_rotated_nose * scale

    # 7. Add the scaled, rotated vector to the destination eye midpoint to get the target nose position
    dest_nose_tip = np.float32(eye_midpoint_dst + vec_nose_dst)

    # Define the 3 destination points corresponding to the source points
    pts_dst = np.float32([dest_left_eye, dest_right_eye, dest_nose_tip])

    # --- Calculate Affine Matrix and Warp Image + Mask ---
    try:
        # Calculate the 2x3 affine matrix mapping pts_src to pts_dst
        M = cv2.getAffineTransform(pts_src, pts_dst)
        print(f"  -> Calculated Affine Matrix M for {os.path.basename(image_path)}")

        # Warp the original BGR image onto the final canvas size using the matrix
        # INTER_CUBIC provides better quality interpolation for the image itself
        warped_image_cv = cv2.warpAffine(
            image_bgr, M, final_canvas_size, flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0) # Fill empty areas with black
        )
        print(f"  -> Warped image successfully.")

        # --- Create and Warp Alpha Mask ---
        # Create a mask the same size as the *original* input image, filled with white (255)
        orig_mask = np.ones((img_h, img_w), dtype=np.uint8) * 255
        # Warp this white mask using the *same* affine transform M
        # Use INTER_NEAREST to keep mask edges sharp and avoid semi-transparent pixels
        # Fill empty areas in the warped mask with black (0) for transparency
        warped_mask = cv2.warpAffine(
            orig_mask, M, final_canvas_size, flags=cv2.INTER_NEAREST,
            borderMode=cv2.BORDER_CONSTANT, borderValue=(0)
        )
        print(f"  -> Warped alpha mask successfully.")

    except Exception as e:
        print(f"  Error during Affine Transform/Warp for {os.path.basename(image_path)}: {e}")
        return None, None, 'error_warp', None, None # Return None for image and mask

    # --- Return warped image (BGR) and warped mask (grayscale) ---
    return warped_image_cv, warped_mask, 'success', dest_left_eye, dest_right_eye

# --- Main Execution Logic ---

def main():
    parser = argparse.ArgumentParser(
        description="Align faces in images using affine transformation based on landmarks.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter # Show default values in help
    )
    parser.add_argument("--input_folder", type=str, required=True, help="Folder containing input images")
    parser.add_argument("--output_folder", type=str, required=True, help="Folder to save processed images")
    parser.add_argument("--reference", type=str, required=True, help="Reference image, list, or folder path for target face")
    parser.add_argument("--target_face_width", type=int, default=200, help="Target distance between eyes in pixels (controls face scale)")
    parser.add_argument("--use_cnn", action="store_true", help="Use CNN model for face detection (slower, potentially more accurate)")
    parser.add_argument("--jpg", action="store_true", help="Output JPG with white background (default: PNG with transparency)")
    parser.add_argument("--testing", action="store_true", help="Process only the first 10 images for testing")
    parser.add_argument("--debug_draw", action="store_true", help="Save debug images with target eyes marked")
    args = parser.parse_args()

    # --- Set Target Resolution ---
    final_canvas_width = 12228
    final_canvas_height = 6912
    final_canvas_size = (final_canvas_width, final_canvas_height)
    # Define the anchor point where the face center (eye midpoint) will be placed
    canvas_center = (final_canvas_width / 2.0, final_canvas_height / 2.0)
    anchor_point = canvas_center

    print("Loading reference face encodings...")
    reference_encodings = load_reference_encodings(args.reference)
    if not reference_encodings and not args.jpg: # Warn if falling back to first face without references
         print("Warning: No valid reference encodings loaded. Will attempt to use first face detected.")
         # Note: Fallback without references might not be consistent for match cuts.

    print(f"\n--- Processing Images ({'CNN' if args.use_cnn else 'HOG'} detector) ---")
    try:
        # Get and sort list of image files to process
        image_files = sorted([f for f in os.listdir(args.input_folder)
                              if f.lower().endswith((".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"))])
    except FileNotFoundError:
        print(f"Error: Input folder not found: {args.input_folder}")
        return
    if not image_files:
        print(f"Error: No images found in {args.input_folder}")
        return

    count = 0         # Total images attempted
    processed_count = 0 # Images where warp succeeded
    saved_count = 0     # Images successfully saved

    # --- Prepare Output Directories ---
    processed_dir = os.path.join(args.output_folder, "_processed")
    debug_dir = os.path.join(args.output_folder, "_debug_affine")
    output_dirs_to_create = [processed_dir]
    if args.debug_draw:
        output_dirs_to_create.append(debug_dir)

    for dir_path in output_dirs_to_create:
        if not os.path.exists(dir_path):
            try:
                os.makedirs(dir_path)
                print(f"Created directory: {dir_path}")
            except OSError as e:
                # If creating the main output directory fails, stop execution
                print(f"Error creating directory {dir_path}: {e}")
                if dir_path == processed_dir:
                    return

    # --- Process Each Image ---
    for filename in image_files:
        input_path = os.path.join(args.input_folder, filename)
        print(f"Processing [{count+1}/{len(image_files)}] {filename}...")

        # Call the processing function to get the warped BGR image and alpha mask
        warped_image_cv, warped_mask, status, dest_le, dest_re = process_image_direct_affine(
            input_path, reference_encodings, args.target_face_width,
            final_canvas_size, anchor_point, args.use_cnn
        )

        count += 1
        # If processing failed (e.g., no face, landmark error, warp error), skip to next image
        if status != 'success':
            print(f"  -> Skipping {filename} (Status: {status})")
            # Check testing limit after skipping
            if args.testing and count >= 10:
                print(f"\nTesting mode: Stopped after attempting {count} images.")
                break
            continue # Go to next file

        processed_count += 1 # Increment count of successfully processed images

        # --- Prepare Final PIL Image for Saving ---
        final_pil_to_save = None # Will hold the Image object ready for saving
        try:
            # Create an RGBA PIL Image using the warped BGR image and the warped alpha mask
            # This is needed as an intermediate step for both PNG and JPG output formats
            if warped_mask is not None:
                # Combine BGR and mask into BGRA using OpenCV
                warped_bgra = cv2.cvtColor(warped_image_cv, cv2.COLOR_BGR2BGRA)
                warped_bgra[:, :, 3] = warped_mask # Set the alpha channel
                # Convert the BGRA OpenCV array to an RGBA PIL Image
                temp_pil_rgba = Image.fromarray(cv2.cvtColor(warped_bgra, cv2.COLOR_BGRA2RGBA))
            else:
                # Fallback if mask failed (should not happen if status=='success')
                print(f"  Warning: Mask missing for {filename} despite success status. Image will be opaque.")
                temp_pil_rgba = Image.fromarray(cv2.cvtColor(warped_image_cv, cv2.COLOR_BGR2RGB)).convert('RGBA')

            # Determine the final image based on the output format flag (--jpg)
            if args.jpg:
                # --- JPG Output: Composite onto White Background ---
                # Create a new white RGB canvas of the final size
                white_canvas = Image.new("RGB", final_canvas_size, (255, 255, 255))
                # Paste the (potentially transparent) RGBA image onto the white canvas.
                # The third argument (temp_pil_rgba) ensures PIL uses the alpha channel as the mask.
                white_canvas.paste(temp_pil_rgba, (0, 0), temp_pil_rgba)
                final_pil_to_save = white_canvas # This RGB image is ready for JPG saving
            else:
                # --- PNG Output: Use the RGBA image directly ---
                final_pil_to_save = temp_pil_rgba # This RGBA image is ready for PNG saving

        except Exception as e:
            print(f"  Error preparing final PIL image for {filename}: {e}")
            # If PIL preparation fails, cannot save or debug draw
            if args.testing and count >= 10:
                print(f"\nTesting mode: Stopped after attempting {count} images.")
                break
            continue # Skip to next file

        # --- Optional Debug Drawing ---
        # Draw target eye markers on the final PIL image (before saving)
        if args.debug_draw and final_pil_to_save: # Check if image exists
            try:
                # Work on a copy to avoid modifying the image to be saved
                debug_img_pil = final_pil_to_save.copy()
                draw = ImageDraw.Draw(debug_img_pil)
                # Target eye coordinates calculated earlier
                le_coords = (int(round(dest_le[0])), int(round(dest_le[1])))
                re_coords = (int(round(dest_re[0])), int(round(dest_re[1])))
                # Draw markers
                draw.line([le_coords, re_coords], fill="lime", width=3) # Green line
                radius = 5
                draw.ellipse((le_coords[0]-radius, le_coords[1]-radius, le_coords[0]+radius, le_coords[1]+radius), outline="lime", width=2)
                draw.ellipse((re_coords[0]-radius, re_coords[1]-radius, re_coords[0]+radius, re_coords[1]+radius), outline="lime", width=2)

                # Save the debug image (always as PNG for potential transparency)
                basename = os.path.splitext(filename)[0]
                debug_path = os.path.join(debug_dir, f"debug_{basename}.png")
                debug_img_pil.save(debug_path)
            except Exception as e:
                print(f"  Error creating debug image for {filename}: {e}")
                # Non-fatal error, continue saving the main image

        # --- Save Final Image ---
        if final_pil_to_save: # Check again if the final image was prepared successfully
            basename = os.path.splitext(filename)[0]
            ext = ".jpg" if args.jpg else ".png"
            output_filename = f"aligned_{basename}{ext}"
            output_path = os.path.join(processed_dir, output_filename)
            try:
                if args.jpg:
                    # Save the RGB image (composited on white) as JPG
                    final_pil_to_save.save(output_path, quality=95)
                else:
                    # Save the RGBA image as PNG
                    final_pil_to_save.save(output_path)
                print(f"Saved: {output_filename}")
                saved_count += 1 # Increment count of successfully saved images
            except Exception as e:
                 print(f"Error saving {output_path}: {e}")
                 # Do not increment saved_count if save fails

        # Check testing limit after successful processing and saving attempt
        if args.testing and count >= 10:
            print(f"\nTesting mode: Stopped after attempting {count} images.")
            break # Exit the loop

    # --- Final Summary ---
    print(f"\n--- Processing Complete ---")
    print(f"Attempted to process: {count} images")
    print(f"Successfully saved: {saved_count} images")
    print(f"Skipped or failed: {count - saved_count} images") # Images attempted minus saved
    print(f"Aligned images saved to: {processed_dir}")
    if args.debug_draw:
        print(f"Debug images saved to: {debug_dir}")

if __name__ == "__main__":
    main()