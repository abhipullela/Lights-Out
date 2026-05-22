import subprocess

input_file = "program.elf"
output_file = "program.hex"

subprocess.run([
    "arm-none-eabi-objcopy",
    "-O",
    "ihex",
    input_file,
    output_file
])

print("Conversion complete!")