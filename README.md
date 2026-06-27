# Blue Pill J-Link Debug Repair Guide

This documents the exact repair path used for this project so it can be repeated without guessing.

## What Was Wrong

The J-Link connection was not the real problem. OpenOCD could see the probe and the STM32 over SWD.

The final root cause was the project memory map:

- OpenOCD detected `flash size = 32kbytes`.
- SRAM reads near `0x20004ff0` failed.
- The linker script previously placed `_estack` at `0x20005000`, which assumes 20 KB RAM.
- This chip behaves like a 32 KB flash / 10 KB RAM STM32F103 variant.
- The CPU faulted before reaching `main()` because the initial stack pointer was outside real SRAM.

## Files Changed

The important files are:

- `Dockerfile`
- `.vscode/tasks.json`
- `.vscode/launch.json`
- `.vscode/settings.json`
- `STM32F103XX_FLASH.ld`
- `Makefile`
- `Core/Src/main.c`

## Step 1: Make Docker Toolchain Complete

File: `Dockerfile`

In the embedded toolchain install block, make sure these packages are present:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    libnewlib-arm-none-eabi \
    libnewlib-dev \
    gdb-multiarch \
    openocd \
    make \
    git \
    python3 \
    && rm -rf /var/lib/apt/lists/*
```

Line-by-line reason:

- `gcc-arm-none-eabi`: ARM compiler for STM32 firmware.
- `binutils-arm-none-eabi`: provides objcopy, objdump, nm, size, etc.
- `libnewlib-arm-none-eabi`: embedded C library for ARM targets.
- `libnewlib-dev`: headers such as `errno.h` and `sys/stat.h`.
- `gdb-multiarch`: debugger used by the wrapper as ARM GDB.
- `openocd`: starts the GDB server and talks to J-Link.

Rebuild the image:

```bash
docker build -t generic-modbus-dev .
```

Expected result:

- Docker image builds successfully.
- The SEGGER J-Link `.deb` may complain about `udevadm` inside Docker; this Dockerfile allows that with `|| true`.

## Step 2: Fix OpenOCD Tasks

File: `.vscode/tasks.json`

The OpenOCD server task must use J-Link SWD plus the STM32F1 target:

```json
"args": [
  "-f",
  "interface/jlink.cfg",
  "-c",
  "transport select swd",
  "-f",
  "target/stm32f1x.cfg",
  "-c",
  "adapter speed 1000"
]
```

Line-by-line reason:

- `interface/jlink.cfg`: tells OpenOCD to use J-Link.
- `transport select swd`: Blue Pill uses SWD pins, not full JTAG.
- `target/stm32f1x.cfg`: correct OpenOCD target script for STM32F103.
- `adapter speed 1000`: conservative 1 MHz SWD clock.

Do not use:

```json
"board/stm32f1x.cfg"
```

That file does not exist in this OpenOCD install.

Do not use:

```json
"board/st_nucleo_wb55.cfg"
```

That is for an STM32WB55 Nucleo board, not a Blue Pill.

The flash task must program the real ELF name:

```json
"program build/bluepill.elf verify reset exit"
```

The project builds `build/bluepill.elf`, not `build/test.elf`.

## Step 3: Fix VS Code Cortex-Debug Launch

File: `.vscode/launch.json`

Use the Cortex-Debug configuration named:

```json
"name": "Build + Flash + Debug Blue Pill"
```

Important lines:

```json
"type": "cortex-debug",
"request": "launch",
"servertype": "external",
"gdbTarget": "localhost:3333",
"executable": "${workspaceFolder}/build/bluepill.elf",
"device": "STM32F103C6",
"gdbPath": "${workspaceFolder}/tools/docker-toolchain/arm-none-eabi-gdb",
"objdumpPath": "${workspaceFolder}/tools/docker-toolchain/arm-none-eabi-objdump",
"preLaunchTask": "Build + Start OpenOCD GDB Server (Docker)"
```

Line-by-line reason:

- `type: cortex-debug`: uses the STM32-aware VS Code debugger.
- `servertype: external`: OpenOCD is started by a VS Code task, not by Cortex-Debug itself.
- `gdbTarget: localhost:3333`: OpenOCD GDB server port.
- `executable`: points to the ELF with symbols.
- `device: STM32F103C6`: matches the detected 32 KB flash / 10 KB RAM part.
- `gdbPath`: uses the Docker wrapper for GDB.
- `preLaunchTask`: builds firmware and starts OpenOCD before GDB connects.

Add deterministic launch commands:

```json
"overrideLaunchCommands": [
  "monitor reset halt",
  "load",
  "monitor reset halt",
  "tbreak main",
  "continue"
]
```

Line-by-line reason:

- `monitor reset halt`: reset the MCU and stop at reset.
- `load`: program the ELF through GDB/OpenOCD.
- `monitor reset halt`: reset again after programming.
- `tbreak main`: set a temporary hardware breakpoint at `main`.
- `continue`: run until `main`.

Important: if VS Code shows `C/C++ Runner: Debug Session`, do not use it. That is for desktop C programs and points at a non-existent host executable. Use `Build + Flash + Debug Blue Pill`.

## Step 4: Fix Makefile Target Define

File: `Makefile`

Use:

```make
C_DEFS =  \
-DUSE_HAL_DRIVER \
-DSTM32F103x6
```

Line-by-line reason:

- `USE_HAL_DRIVER`: keeps ST HAL headers in the expected mode.
- `STM32F103x6`: selects the low-density STM32F103 memory/device definitions.

Do not use `STM32F103xB` for this board if OpenOCD reports only `32kbytes` flash.

## Step 5: Fix Linker Memory Map

File: `STM32F103XX_FLASH.ld`

Set:

```ld
MEMORY
{
  RAM    (xrw)    : ORIGIN = 0x20000000,   LENGTH = 10K
  FLASH    (rx)    : ORIGIN = 0x8000000,   LENGTH = 32K
}
```

Line-by-line reason:

- `RAM ORIGIN = 0x20000000`: STM32F1 SRAM starts here.
- `LENGTH = 10K`: detected usable SRAM ends at `0x20002800`.
- `FLASH ORIGIN = 0x8000000`: STM32 flash starts here.
- `LENGTH = 32K`: OpenOCD detected `flash size = 32kbytes`.

This makes:

```ld
_estack = ORIGIN(RAM) + LENGTH(RAM);
```

become:

```text
_estack = 0x20002800
```

That is inside valid RAM.

## Step 6: Fix `main.c`

File: `Core/Src/main.c`

Use:

```c
#include <stdint.h>

int main(void)
{
  volatile uint32_t test = 5U;

  while (1)
  {
    test = test + test;
  }
}
```

Line-by-line reason:

- `#include <stdint.h>`: gives fixed-width integer type `uint32_t`.
- `int main(void)`: correct C entry point signature.
- `volatile uint32_t test = 5U`: keeps the variable visible to the debugger; compiler must not optimize it away.
- `while (1)`: embedded firmware should not return from `main`.
- `test = test + test`: simple instruction to step over while debugging.

## Step 7: Stop Stale Debug Containers

If OpenOCD says a port is already in use, check for old containers:

```bash
docker ps --filter ancestor=generic-modbus-dev --format "{{.ID}} {{.Command}} {{.Status}} {{.Ports}}"
```

If you see old `openocd` or `gdb-multiarch` containers, stop them:

```bash
docker stop <container-id-1> <container-id-2>
```

This releases ports `3333`, `4444`, and `6666`.

## Step 8: Clean and Rebuild Firmware

Run:

```bash
./tools/docker-make.sh clean
./tools/docker-make.sh -j
```

Expected successful build output includes:

```text
arm-none-eabi-size build/bluepill.elf
   text    data     bss     dec     hex filename
    644       0    1568    2212     8a4 build/bluepill.elf
```

Your exact size can change after code edits, but the build must create:

```text
build/bluepill.elf
build/bluepill.hex
build/bluepill.bin
```

## Step 9: Verify J-Link and STM32 Connection

Run:

```bash
./tools/docker-openocd.sh \
  -f interface/jlink.cfg \
  -c "transport select swd" \
  -f target/stm32f1x.cfg \
  -c "adapter speed 1000" \
  -c init \
  -c targets \
  -c shutdown
```

Expected important output:

```text
Info : J-Link V9 ...
Info : VTarget = 3.35x V
Info : SWD DPIDR 0x1ba01477
Info : stm32f1x.cpu: hardware has 6 breakpoints, 4 watchpoints
```

This means:

- J-Link is detected.
- The target board has power.
- SWD communication works.
- The CPU can be halted.

## Step 10: Verify Actual RAM Size

This was the key diagnosis step.

Run:

```bash
./tools/docker-openocd.sh \
  -f interface/jlink.cfg \
  -c "transport select swd" \
  -f target/stm32f1x.cfg \
  -c "adapter speed 1000" \
  -c init \
  -c "mdw 0x200027f0 4" \
  -c "mdw 0x20004ff0 4" \
  -c shutdown
```

Observed result:

- `0x200027f0` was readable.
- `0x20004ff0` failed.

Conclusion:

- Stack top must not be `0x20005000`.
- Correct stack top is `0x20002800`.
- Linker RAM length must be `10K`.

## Step 11: Verify `_estack`

Run:

```bash
./tools/docker-toolchain/arm-none-eabi-nm -n build/bluepill.elf | rg "_estack|main|Reset_Handler|Default_Handler"
```

Expected important output:

```text
08000200 T main
08000210 W Reset_Handler
08000260 T Default_Handler
20002800 R _estack
```

The important line is:

```text
20002800 R _estack
```

That confirms the stack is inside real SRAM.

## Step 12: Flash and Verify

Run:

```bash
./tools/docker-openocd.sh \
  -f interface/jlink.cfg \
  -c "transport select swd" \
  -f target/stm32f1x.cfg \
  -c "adapter speed 1000" \
  -c "program build/bluepill.elf verify reset exit"
```

Expected output:

```text
** Programming Started **
Info : flash size = 32kbytes
** Programming Finished **
** Verify Started **
** Verified OK **
** Resetting Target **
```

## Step 13: Verify Debug Reaches `main`

Start OpenOCD in one terminal:

```bash
./tools/docker-openocd.sh \
  -f interface/jlink.cfg \
  -c "transport select swd" \
  -f target/stm32f1x.cfg \
  -c "adapter speed 1000"
```

Then connect GDB in another terminal:

```bash
./tools/docker-toolchain/arm-none-eabi-gdb \
  -batch \
  -ex "target extended-remote localhost:3333" \
  -ex "monitor reset halt" \
  -ex "load" \
  -ex "monitor reset halt" \
  -ex "break Default_Handler" \
  -ex "tbreak main" \
  -ex "continue" \
  -ex "info registers pc sp" \
  -ex "monitor shutdown" \
  build/bluepill.elf
```

Expected output:

```text
Temporary breakpoint 2, main () at Core/Src/main.c:5
pc             0x8000202
sp             0x200027f8
shutdown command invoked
```

This confirms:

- The firmware no longer faults before `main`.
- The stack pointer is inside valid RAM.
- GDB can debug through OpenOCD and J-Link.

## VS Code Usage

In Run and Debug, select:

```text
Build + Flash + Debug Blue Pill
```

Do not select:

```text
C/C++ Runner: Debug Session
```

Reason:

- `Build + Flash + Debug Blue Pill` uses Cortex-Debug, OpenOCD, J-Link, and the ARM ELF.
- `C/C++ Runner: Debug Session` is for host/desktop C programs and will not debug the STM32 board.

## Quick Recovery Checklist

If debugging breaks again:

1. Stop stale containers:

   ```bash
   docker ps --filter ancestor=generic-modbus-dev --format "{{.ID}} {{.Command}} {{.Status}} {{.Ports}}"
   docker stop <ids>
   ```

2. Rebuild:

   ```bash
   ./tools/docker-make.sh clean
   ./tools/docker-make.sh -j
   ```

3. Flash verify:

   ```bash
   ./tools/docker-openocd.sh -f interface/jlink.cfg -c "transport select swd" -f target/stm32f1x.cfg -c "adapter speed 1000" -c "program build/bluepill.elf verify reset exit"
   ```

4. Use the VS Code configuration:

   ```text
   Build + Flash + Debug Blue Pill
   ```

****
