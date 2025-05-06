#!/usr/bin/env python3
import os
import torch
from pathlib import Path
import torchaudio
import numpy as np
from demucs.pretrained import get_model
from demucs.apply import apply_model

def extract_vocals(input_file, output_dir="extracted_vocals"):
    """
    Extract vocals from an audio file using Demucs.
    
    Args:
        input_file (str): Path to the input .wav file
        output_dir (str): Directory to save the extracted vocals
    
    Returns:
        str: Path to the extracted vocals file
    """
    print(f"Loading audio file: {input_file}")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Load the audio file using librosa instead of torchaudio
    import librosa
    audio_np, sample_rate = librosa.load(input_file, sr=None, mono=False)
    
    # Convert librosa output to torch tensor
    if audio_np.ndim == 1:
        # If mono, reshape to [1, length]
        waveform = torch.tensor(audio_np).unsqueeze(0)
    else:
        # If already multi-channel, convert to [channels, length]
        waveform = torch.tensor(audio_np)
    
    # Ensure audio is in proper format for Demucs (stereo)
    if waveform.shape[0] == 1:
        # Convert mono to stereo by duplicating the channel
        waveform = waveform.repeat(2, 1)
    elif waveform.shape[0] > 2:
        waveform = waveform[:2]  # Keep only first two channels if more than 2
    
    # Load the Demucs model (using "htdemucs" which is a high-quality model)
    print("Loading Demucs model...")
    model = get_model("htdemucs")
    model.eval()
    
    # Move model to GPU if available
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")
    model = model.to(device)
    
    # Apply the model to separate sources
    print("Separating audio sources...")
    # Move audio to the same device as the model
    waveform = waveform.to(device)
    
    # Demucs expects the input in shape (batch, channels, time)
    waveform = waveform.unsqueeze(0)  # Add batch dimension
    
    with torch.no_grad():
        sources = apply_model(model, waveform, device=device)[0]
    
    # The output of Demucs has the shape (sources, channels, time)
    # Extract the vocals (typically index 0 in htdemucs is vocals)
    vocals_idx = model.sources.index("vocals")
    vocals = sources[vocals_idx].cpu()
    
    # Save the vocal track using torchaudio
    output_file = os.path.join(output_dir, f"vocals_{os.path.basename(input_file)}")
    print(f"Saving vocals to: {output_file}")
    
    # Use scipy to save the file instead of torchaudio
    from scipy.io import wavfile
    vocals_np = vocals.numpy()
    wavfile.write(output_file, sample_rate, vocals_np.T)  # transpose to [time, channels]
    
    return output_file

if __name__ == "__main__":
    # Hardcoded input file path - replace with your actual file path
    input_wav_file = "/Users/billy/Dropbox/Projects/Zoe+Charlie/ASSETS/Zoe/Zoe_Dad_Audio.wav"
    
    # Extract vocals
    output_file = extract_vocals(input_wav_file)
    print(f"Vocal extraction complete. Vocals saved to: {output_file}")