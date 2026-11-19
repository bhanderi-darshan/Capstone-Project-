# Tooling & Verification Environment Setup

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author:** Darshan Bhanderi  

---

## 1. Required Tools

| Tool | Recommended Version | Purpose | License |
|:---|:---:|:---|:---:|
| **Icarus Verilog (`iverilog`)** | v11.0 or v12.0+ | IEEE 1800-2012 SystemVerilog simulation | Open Source (GPL) |
| **Icarus Runtime (`vvp`)** | Included with iverilog | Simulation runtime engine | Open Source (GPL) |
| **GTKWave** | v3.3.100+ | Value Change Dump (`.vcd`) waveform inspection | Open Source (GPL) |
| **Git** | v2.25+ | Source code version control | Open Source (GPL) |

---

## 2. Installation Instructions

### 2.1 Ubuntu / Debian Linux
```bash
sudo apt-get update
sudo apt-get install -y iverilog gtkwave git
```

### 2.2 macOS (via Homebrew)
```bash
brew install icarus-verilog gtkwave git
```

### 2.3 Windows
- Install via **Chocolatey**:
  ```powershell
  choco install icarus-verilog
  ```
- Or download the official Windows binary installer from:
  [http://bleyer.org/icarus/](http://bleyer.org/icarus/)
- Ensure `iverilog` and `vvp` are added to your system's `PATH`.

---

## 3. Toolchain Execution
All simulation scripts located in `sim/` automatically detect whether `iverilog` and `vvp` are installed on the system `PATH` or present locally.
