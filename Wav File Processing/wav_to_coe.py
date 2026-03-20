import wave
import numpy as np
import struct
import sys
import os

class WavToCoefficients:
    def __init__(self, wav_file_path):
        """
        Initialize with WAV file path
        """
        self.wav_file = wav_file_path
        self.sample_rate = None
        self.num_channels = None
        self.sample_width = None
        self.num_frames = None
        self.audio_data = None
        
    def read_wav_file(self) -> np.ndarray:
        """
        Read WAV file and extract audio data
        Returns normalized numpy array of audio samples
        """
        try:
            with wave.open(self.wav_file, 'rb') as wav:
                # Get WAV file parameters
                self.num_channels = wav.getnchannels()
                self.sample_width = wav.getsampwidth()
                self.sample_rate = wav.getframerate()
                self.num_frames = wav.getnframes()
                
                print(f"WAV File Info:")
                print(f"  Channels: {self.num_channels}")
                print(f"  Sample width: {self.sample_width} bytes ({self.sample_width*8}-bit)")
                print(f"  Sample rate: {self.sample_rate} Hz")
                print(f"  Number of frames: {self.num_frames:,}")
                print(f"  Duration: {self.num_frames/self.sample_rate:.2f} seconds")
                
                # Read all frames
                frames = wav.readframes(self.num_frames)
                
                # Convert to numpy array based on sample width
                if self.sample_width == 1:
                    # 8-bit audio (unsigned)
                    dtype = np.uint8
                    fmt = f"{self.num_frames * self.num_channels}B"
                    data = np.array(struct.unpack(fmt, frames), dtype=dtype)
                    # Convert to float in range [-1, 1]
                    data = (data - 128) / 128.0
                    
                elif self.sample_width == 2:
                    # 16-bit audio (signed)
                    dtype = np.int16
                    fmt = f"{self.num_frames * self.num_channels}h"
                    data = np.array(struct.unpack(fmt, frames), dtype=dtype)
                    # Convert to float in range [-1, 1]
                    data = data / 32768.0
                    
                elif self.sample_width == 3:
                    # 24-bit audio (special handling)
                    data = self._read_24bit(frames)
                    data = data / 8388608.0  # 2^23
                    
                elif self.sample_width == 4:
                    # 32-bit audio
                    dtype = np.int32
                    fmt = f"{self.num_frames * self.num_channels}i"
                    data = np.array(struct.unpack(fmt, frames), dtype=dtype)
                    data = data / 2147483648.0  # 2^31
                
                # Reshape for multi-channel
                if self.num_channels > 1:
                    self.audio_data = data.reshape(-1, self.num_channels)
                else:
                    self.audio_data = data
                    
                return self.audio_data
                
        except Exception as e:
            print(f"Error reading WAV file: {e}")
            return None
    
    def _read_24bit(self, frames: bytes) -> np.ndarray:
        """Helper function to read 24-bit audio data"""
        samples = []
        for i in range(0, len(frames), 3):
            # Combine 3 bytes into 24-bit signed integer
            sample = frames[i] | (frames[i+1] << 8) | (frames[i+2] << 16)
            # Handle sign extension
            if sample & 0x800000:
                sample |= ~0xffffff
            samples.append(sample)
        return np.array(samples, dtype=np.int32)
    
    def extract_all_coefficients(self, channel: int = 0) -> np.ndarray:
        """
        Extract ALL coefficients from the audio file (no skipping)
        
        Args:
            channel: Which channel to use (0 for first channel)
            
        Returns:
            numpy array of all coefficients
        """
        if self.audio_data is None:
            print("No audio data loaded. Call read_wav_file() first.")
            return None
        
        # Select channel
        if self.num_channels > 1:
            if channel >= self.num_channels:
                print(f"Channel {channel} out of range. Using channel 0.")
                channel = 0
            data = self.audio_data[:, channel]
            print(f"Using channel {channel} of {self.num_channels}")
        else:
            data = self.audio_data
        
        print(f"Extracting ALL {len(data)} coefficients (no data loss)")
        return data
    
    def extract_specific_range(self, start_sample: int, num_coeffs: int, channel: int = 0) -> np.ndarray:
        """
        Extract a specific range of coefficients
        
        Args:
            start_sample: Starting sample index (0 = beginning)
            num_coeffs: Number of coefficients to extract
            channel: Which channel to use
            
        Returns:
            numpy array of coefficients
        """
        if self.audio_data is None:
            print("No audio data loaded. Call read_wav_file() first.")
            return None
        
        # Select channel
        if self.num_channels > 1:
            if channel >= self.num_channels:
                print(f"Channel {channel} out of range. Using channel 0.")
                channel = 0
            data = self.audio_data[:, channel]
        else:
            data = self.audio_data
        
        # Calculate end sample
        end_sample = min(start_sample + num_coeffs, len(data))
        data = data[start_sample:end_sample]
        
        actual_extracted = len(data)
        print(f"Extracted {actual_extracted} coefficients (requested {num_coeffs})")
        if actual_extracted < num_coeffs:
            print(f"Warning: Reached end of file. Only {actual_extracted} coefficients available.")
        
        return data
    
    def quantize_coefficients(self, coeffs: np.ndarray, bits: int = 16, 
                             signed: bool = True) -> np.ndarray:
        """
        Quantize floating point coefficients to fixed-point
        
        Args:
            coeffs: Floating point coefficients
            bits: Number of bits for quantization
            signed: Whether to use signed representation
            
        Returns:
            Quantized integer coefficients
        """
        if signed:
            max_val = 2**(bits-1) - 1
            min_val = -2**(bits-1)
        else:
            max_val = 2**bits - 1
            min_val = 0
        
        # Scale and quantize
        scaled = coeffs * max_val
        quantized = np.round(scaled).astype(np.int64)
        
        # Clip to range
        quantized = np.clip(quantized, min_val, max_val)
        
        return quantized
    
    def generate_verilog_mem(self, coeffs: np.ndarray, module_name: str = "coeff_mem",
                            data_width: int = 16, radix: str = 'h') -> str:
        """
        Generate Verilog memory initialization
        
        Args:
            coeffs: Coefficient array
            module_name: Name for the Verilog module
            data_width: Bit width of coefficients
            radix: 'b' (binary), 'h' (hex), or 'd' (decimal)
        """
        verilog = f"""// Auto-generated coefficient memory
// Generated from: {os.path.basename(self.wav_file)}
// Date: {np.datetime64('now')}
// Parameters: {len(coeffs)} coefficients, {data_width}-bit
// Sample Rate: {self.sample_rate} Hz, Duration: {len(coeffs)/self.sample_rate:.2f}s

module {module_name} #(
    parameter DATA_WIDTH = {data_width},
    parameter DEPTH = {len(coeffs)}
)(
    input wire clk,
    input wire rst,
    input wire [$clog2(DEPTH)-1:0] addr,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg done
);

    // Coefficient memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [$clog2(DEPTH)-1:0] addr_reg;
    
    // Initialize memory
    initial begin
"""
        # Add coefficient initialization
        for i, coeff in enumerate(coeffs):
            if radix == 'h':
                val_str = f"{int(coeff) & ((1<<data_width)-1):0{data_width//4}X}"
                verilog += f"        mem[{i}] = {data_width}'h{val_str};\n"
            elif radix == 'b':
                val_str = f"{int(coeff) & ((1<<data_width)-1):0{data_width}b}"
                verilog += f"        mem[{i}] = {data_width}'b{val_str};\n"
            else:
                verilog += f"        mem[{i}] = {data_width}'d{int(coeff)};\n"
        
        verilog += f"""    end
    
    // Read operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= {{DATA_WIDTH{{1'b0}}}};
            done <= 1'b0;
            addr_reg <= {{$clog2(DEPTH){{1'b0}}}};
        end else begin
            addr_reg <= addr;
            data_out <= mem[addr_reg];
            if (addr_reg == DEPTH-1)
                done <= 1'b1;
            else
                done <= 1'b0;
        end
    end

endmodule
"""
        return verilog

def main():
    """
    Main function with no data loss
    """
    if len(sys.argv) < 2:
        print("\nUsage: python wav_to_coeffs.py <wav_file> [num_coeffs] [channel]")
        print("\nExamples:")
        print("  python wav_to_coeffs.py audio.wav              # Extract ALL coefficients")
        print("  python wav_to_coeffs.py audio.wav 1024         # Extract first 1024 coefficients")
        print("  python wav_to_coeffs.py audio.wav 1024 1       # Extract 1024 coeffs from channel 1")
        print("  python wav_to_coeffs.py audio.wav all 0        # Extract ALL coeffs from channel 0\n")
        sys.exit(1)
    
    wav_file = sys.argv[1]
    
    # Parse arguments
    num_coeffs = None
    channel = 0
    
    if len(sys.argv) >= 3:
        if sys.argv[2].lower() != 'all':
            num_coeffs = int(sys.argv[2])
    
    if len(sys.argv) >= 4:
        channel = int(sys.argv[3])
    
    # Create converter instance
    converter = WavToCoefficients(wav_file)
    
    # Read WAV file
    converter.read_wav_file()
    
    # Extract coefficients (NO SKIPPING!)
    if num_coeffs is None:
        # Extract ALL coefficients
        print(f"\nExtracting ALL coefficients from channel {channel}...")
        coeffs = converter.extract_all_coefficients(channel=channel)
    else:
        # Extract specific number from beginning
        print(f"\nExtracting first {num_coeffs} coefficients from channel {channel}...")
        coeffs = converter.extract_specific_range(start_sample=0, 
                                                  num_coeffs=num_coeffs, 
                                                  channel=channel)
    
    if coeffs is not None and len(coeffs) > 0:
        print(f"\n✅ Successfully extracted {len(coeffs)} coefficients")
        print(f"   Min: {np.min(coeffs):.6f}")
        print(f"   Max: {np.max(coeffs):.6f}")
        print(f"   Mean: {np.mean(coeffs):.6f}")
        print(f"   Std: {np.std(coeffs):.6f}")
        
        # Quantize to 16-bit fixed-point
        quantized = converter.quantize_coefficients(coeffs, bits=16, signed=True)
        
        # Generate Verilog memory
        verilog_code = converter.generate_verilog_mem(quantized, 
                                                      module_name="audio_coeff_mem",
                                                      data_width=16)
        
        with open("coeff_mem.v", "w") as f:
            f.write(verilog_code)
        print("\n✅ Verilog file generated: coeff_mem.v")
        
        # Print first 10 coefficients as example
        print("\nFirst 10 coefficients (quantized):")
        for i in range(min(10, len(quantized))):
            print(f"  coeff[{i}] = {quantized[i]:6d} (0x{quantized[i] & 0xFFFF:04X})")
        
        print(f"\nTotal coefficients in memory: {len(quantized)}")
        print(f"This represents {len(quantized)/converter.sample_rate:.2f} seconds of audio")
    else:
        print("❌ Failed to extract coefficients")

if __name__ == "__main__":
    main()
