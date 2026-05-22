# Micro:bit Project – Running Instructions

This project is written in ARM assembly for the BBC micro:bit v2.  
The source file is `main.S` and the build environment is **COMP6300**.

---

## File locations

After extracting the provided zip file, copy the files to the following locations inside your `comp2300-2022-lab-pack-1-main` repository:

```
comp2300-2022-lab-pack-1-main/
└── week-1/
    └── src/
        └── main.S          ← paste your main.S here
    └── convert.py          ← already present at this level
```

> **Note:** `convert.py` lives in the `week-1/` folder (same level as the `Makefile`), not inside `src/`.  
> `main.S` lives inside `week-1/src/`.

---

## Prerequisites

- The **COMP6300 toolchain** installed and on your `PATH`  
  (see `comp2300-toolchain/setup.md` in your repository root)
- A BBC micro:bit v2 with a USB cable

---

## Method 1 — Flash directly with `make upload`

This is the simplest method. It builds the project and flashes the binary straight to the micro:bit over USB in one step.

**Step 1 — Connect the micro:bit**  
Plug the micro:bit into your computer via USB before running any commands.

**Step 2 — Navigate to the week-1 folder**
```bash
cd comp2300-2022-lab-pack-1-main/week-1
```

**Step 3 — Paste your code**  
Replace the contents of `src/main.S` with the `main.S` from the provided zip file.

**Step 4 — Clean previous build output**
```bash
make clean
```

**Step 5 — Build**
```bash
make
```

**Step 6 — Upload to micro:bit**
```bash
make upload
```

The program will start running on the micro:bit immediately after flashing.

---

## Method 2 — Manual drag-and-drop via `convert.py`

Use this method if `make upload` does not work on your machine, or if you prefer to copy the hex file manually.

**Step 1 — Navigate to the week-1 folder**
```bash
cd comp2300-2022-lab-pack-1-main/week-1
```

**Step 2 — Paste your code**  
Replace the contents of `src/main.S` with the `main.S` from the provided zip file.

**Step 3 — Clean previous build output**
```bash
make clean
```

**Step 4 — Build**
```bash
make
```

**Step 5 — Convert the binary to a hex file**
```bash
python3 convert.py
```

This regenerates `program.hex` in the `week-1/` folder.

**Step 6 — Connect the micro:bit**  
Plug the micro:bit into your computer via USB. A drive called **MICROBIT** will appear in your file manager.

**Step 7 — Copy the hex file**  
Drag and drop (or copy) `program.hex` into the **MICROBIT** drive.  
The micro:bit will reboot and the program will start running automatically.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `make upload` says device not found | Ensure micro:bit is plugged in before running the command |
| MICROBIT drive does not appear | Try a different USB cable — some cables are charge-only |
| `python3 convert.py` not found | Ensure Python 3 is installed: `python3 --version` |
| Build errors after pasting `main.S` | Run `make clean` first, then `make` again |
