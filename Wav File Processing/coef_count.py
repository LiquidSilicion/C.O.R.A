#!/usr/bin/env python3
"""
Simple script to count coefficients in a WAV file
Usage: python count_coeffs.py <your_audio_file.wav>
"""

import wave
import sys
import os

def count_coefficients(wav_file_path):
    """
    Count the number of coefficients (samples) in a WAV file
    """
    try:
        # Open the WAV file
        with wave.open(wav_file_path, 'rb') as wav:
            # Get file parameters
            num_channels = wav.getnchannels()
            sample_width = wav.getsampwidth()
            frame_rate = wav.getframerate()
            num_frames = wav.getnframes()
            
            # Calculate total samples (coefficients)
            total_samples = num_frames * num_channels
            
            # Calculate duration
            duration = num_frames / frame_rate
            
            # Print results
            print("\n" + "="*50)
            print(f"FILE: {os.path.basename(wav_file_path)}")
            print("="*50)
            print(f"Sample Rate:         {frame_rate} Hz")
            print(f"Number of Channels:  {num_channels}")
            print(f"Sample Width:        {sample_width} bytes ({sample_width*8}-bit)")
            print(f"Total Frames:        {num_frames:,} frames")
            print("-"*50)
            print(f"TOTAL COEFFICIENTS:  {total_samples:,} samples")
            print(f"  › Per channel:      {num_frames:,} samples")
            print(f"  › All channels:     {total_samples:,} samples")
            print("-"*50)
            print(f"Duration:            {duration:.2f} seconds")
            
            # Additional useful info
            if duration <= 60:
                print(f"                      = {duration:.2f} sec")
            else:
                minutes = int(duration // 60)
                seconds = duration % 60
                print(f"                      = {minutes} min {seconds:.2f} sec")
            
            # File size estimate
            file_size_bytes = total_samples * sample_width
            if file_size_bytes < 1024:
                print(f"Approx. Data Size:   {file_size_bytes} bytes")
            elif file_size_bytes < 1024*1024:
                print(f"Approx. Data Size:   {file_size_bytes/1024:.2f} KB")
            else:
                print(f"Approx. Data Size:   {file_size_bytes/(1024*1024):.2f} MB")
            
            print("="*50 + "\n")
            
            return {
                'total_coefficients': total_samples,
                'per_channel': num_frames,
                'channels': num_channels,
                'sample_rate': frame_rate,
                'duration': duration,
                'sample_width': sample_width
            }
            
    except FileNotFoundError:
        print(f"\n❌ Error: File '{wav_file_path}' not found!")
        return None
    except Exception as e:
        print(f"\n❌ Error reading WAV file: {e}")
        return None

def main():
    # Check if filename was provided
    if len(sys.argv) < 2:
        print("\n🔍 USAGE: python count_coeffs.py <your_audio_file.wav>")
        print("\nExamples:")
        print("  python count_coeffs.py music.wav")
        print("  python count_coeffs.py C:\\Users\\me\\Desktop\\speech.wav")
        print("  python count_coeffs.py ../recordings/audio.wav\n")
        sys.exit(1)
    
    # Get the WAV file path from command line
    wav_file = sys.argv[1]
    
    # Count coefficients
    result = count_coefficients(wav_file)
    
    if result:
        # You can access the values programmatically if needed
        print(f"\n✅ Found {result['total_coefficients']} total coefficients")
        print(f"   ({result['per_channel']} per channel)")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
