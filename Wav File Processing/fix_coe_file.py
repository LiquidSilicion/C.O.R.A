# fix_coe_file.py
import numpy as np

def create_proper_coe_file(filename, data, radix=16):
    """
    Create a properly formatted COE file
    
    Args:
        filename: Output .coe file name
        data: List of integer values
        radix: 2, 10, or 16
    """
    with open(filename, 'w') as f:
        # Write header - NO SPACES after equals sign!
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")
        
        # Write data in groups of 8 for readability
        for i in range(0, len(data), 8):
            line = ""
            for j in range(8):
                if i + j < len(data):
                    if radix == 16:
                        val_str = f"{data[i+j]:04X}"
                    elif radix == 10:
                        val_str = f"{data[i+j]:d}"
                    else:  # radix == 2
                        val_str = f"{data[i+j]:016b}"
                    
                    line += val_str
                    if i + j < len(data) - 1:
                        line += ", "
            
            f.write(line)
            if i + 8 < len(data):
                f.write(",\n")
            else:
                f.write(";\n")  # Last line ends with semicolon
    
    print(f"✅ Created {filename} with {len(data)} coefficients in radix {radix}")

# Example: Generate 1024 test coefficients
test_data = list(range(1024))  # Replace with your actual coefficients
create_proper_coe_file("fixed_coefficients.coe", test_data, radix=16)
