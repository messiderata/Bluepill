# Firmware Reverse Engineering Report

Scope: this report analyzes the current repository at `/home/philip/stm_project/bluepill`. It does not analyze the other firmware paths visible in the IDE tabs. If the intended target is the LoRaWAN water-level project from another folder, this report should be treated as the Blue Pill bootstrap report only.

Assumptions and limits:

- The current source tree and existing `build/bluepill.map` / `build/bluepill.elf` describe the same firmware revision. The working tree is dirty, and `Core/Src/main.c` currently contains an empty loop.
- Missing source files are not inferred. HAL, CMSIS, interrupt, driver, and application files listed in `.mxproject` but absent from the filesystem are documented as missing.
- The current firmware is a minimal STM32F103 Cortex-M3 image. It is not yet an application with sensors, communications, storage, or scheduling logic.

## 1. System Overview

The firmware currently boots an STM32F103-class Blue Pill target, initializes the C runtime enough to call `main()`, and then spins forever in an empty superloop.

What it does overall:

- Provides a vector table and reset handler in `startup_stm32f103xb.s`.
- Defines flash/RAM layout in `STM32F103XX_FLASH.ld`.
- Links a minimal C program from `Core/Src/main.c`.
- Provides optional newlib syscall and heap support in `Core/Src/syscalls.c` and `Core/Src/sysmem.c`.
- Uses Docker wrapper scripts and VS Code tasks for building, flashing, and debugging.

What it does not currently do:

- No HAL initialization.
- No `SystemClock_Config()`.
- No GPIO, UART, SPI, I2C, ADC, timer, DMA, watchdog, or radio initialization.
- No sensor reads.
- No communications protocol.
- No persistent storage.
- No RTOS, scheduler, task table, or state machine.

Major modules:

| Module | Files | Responsibility | Current status |
| --- | --- | --- | --- |
| Startup/vector table | `startup_stm32f103xb.s` | Sets stack pointer, initializes `.data` and `.bss`, calls C constructors and `main()`, provides weak interrupt handlers. | Present and linked. |
| Application entry | `Core/Src/main.c` | User application entry point. | Present but empty. |
| Linker/memory map | `STM32F103XX_FLASH.ld` | Defines 32 KB flash, 10 KB RAM, stack top, heap/stack reservation, section placement. | Present. |
| Newlib syscall stubs | `Core/Src/syscalls.c` | Provides POSIX-like stubs such as `_read()`, `_write()`, `_exit()`, `_open()`. | Present in source; mostly discarded by linker unless referenced. |
| Heap bridge | `Core/Src/sysmem.c` | Provides `_sbrk()` for `malloc()` if dynamic allocation is used. | Present in source; discarded unless referenced. |
| Build system | `Makefile`, `Dockerfile`, `tools/*.sh` | Builds ELF/HEX/BIN with `arm-none-eabi-gcc`; wraps toolchain/OpenOCD in Docker. | Present. |
| Debug config | `.vscode/tasks.json`, `.vscode/launch.json` | Builds, starts OpenOCD, flashes, and launches Cortex-Debug. | Present. |

Target identity:

- `Makefile` defines `STM32F103x6` and `-mcpu=cortex-m3`.
- `STM32F103XX_FLASH.ld` targets 32 KB flash and 10 KB RAM.
- `.vscode/launch.json` uses device `STM32F103C6`.
- `bluepill.ioc` still names `STM32F103C8Tx`, so the CubeMX metadata does not match the current linker/debug target.
- `BLUEPILL_JLINK_DEBUG_REPAIR_GUIDE.md` explains that OpenOCD detected a 32 KB flash / 10 KB RAM part, and that the linker was intentionally changed to avoid placing `_estack` outside real SRAM.

## 2. Folder Structure

Current important structure:

```text
.
|-- Core/
|   `-- Src/
|       |-- main.c
|       |-- syscalls.c
|       `-- sysmem.c
|-- Drivers/
|-- tools/
|   |-- docker-make.sh
|   |-- docker-openocd.sh
|   |-- docker-toolchain/
|   `-- docs/
|-- build/
|-- .vscode/
|-- startup_stm32f103xb.s
|-- STM32F103XX_FLASH.ld
|-- Makefile
|-- Dockerfile
|-- bluepill.ioc
|-- .mxproject
|-- README.md
`-- BLUEPILL_JLINK_DEBUG_REPAIR_GUIDE.md
```

Directory and file purposes:

- `Core/Src/`: current firmware C sources. This is the only directory with compiled project C code.
- `Core/Inc/`: referenced by `Makefile` via `-ICore/Inc`, but the directory is not present in the current tree.
- `Drivers/`: present as an empty directory. No reusable HAL/CMSIS/board drivers are available in this checkout.
- `tools/`: Docker wrappers for `make`, `openocd`, and ARM binutils/GDB.
- `build/`: generated build outputs such as `bluepill.elf`, `bluepill.hex`, `bluepill.bin`, object files, dependency files, list files, and linker map.
- `.vscode/`: build/debug integration. The Cortex-Debug configuration is the relevant embedded debug setup; the C/C++ Runner config is for host programs and is not the STM32 firmware path.

Important source files:

- `Core/Src/main.c`
  - Defines `int main(void)`.
  - Current body is only `while (1) { }`.
  - No application logic exists here yet.

- `startup_stm32f103xb.s`
  - Defines `g_pfnVectors`, `Reset_Handler`, and `Default_Handler`.
  - Provides weak aliases for all Cortex exception and STM32 peripheral interrupt handlers.
  - Calls `SystemInit`, `__libc_init_array`, and `main` from `Reset_Handler`.

- `STM32F103XX_FLASH.ld`
  - Defines `RAM` as `0x20000000` length `10K`.
  - Defines `FLASH` as `0x08000000` length `32K`.
  - Defines `_estack`, `_Min_Heap_Size = 0x200`, and `_Min_Stack_Size = 0x400`.
  - Places `.isr_vector`, `.text`, `.rodata`, `.data`, `.bss`, and `._user_heap_stack`.

- `Core/Src/syscalls.c`
  - Contains newlib syscall stubs.
  - `_read()` calls weak `__io_getchar()`.
  - `_write()` calls weak `__io_putchar()`.
  - No UART or semihosting implementation is connected here.

- `Core/Src/sysmem.c`
  - Contains `_sbrk()` for heap allocation.
  - Uses `_end`, `_estack`, and `_Min_Stack_Size` linker symbols.
  - Prevents heap growth into the reserved stack region.

Reusable drivers vs application logic:

- Reusable drivers: none present.
- Application logic: only `main()` exists, and it is currently empty.
- Runtime/platform logic: startup, linker script, syscalls, and heap bridge are present.

## 3. Boot Flow

Reset and startup sequence:

1. CPU reset fetches the initial MSP value from vector table entry 0.
   - Current vector value is `_estack = 0x20002800`.
   - This comes from `ORIGIN(RAM) + LENGTH(RAM)` in `STM32F103XX_FLASH.ld`.

2. CPU fetches the reset PC from vector table entry 1.
   - This points to `Reset_Handler` in `startup_stm32f103xb.s`.

3. `Reset_Handler` explicitly reloads the stack pointer.
   - Source: `ldr r0, =_estack`; `mov sp, r0`.

4. `Reset_Handler` attempts to call `SystemInit`.
   - Source has `bl SystemInit`.
   - `SystemInit` is declared weak in `startup_stm32f103xb.s`, but no implementation exists in the current source tree.
   - In the linked ELF symbol table, no `SystemInit` implementation is present. Practically, no clock/system initialization runs in the current firmware.

5. `Reset_Handler` copies initialized `.data` from flash to RAM.
   - Uses `_sidata`, `_sdata`, and `_edata`.
   - Current `.data` size is `0`, so there is nothing to copy.

6. `Reset_Handler` zeroes `.bss`.
   - Uses `_sbss` and `_ebss`.
   - Current `.bss` is `0x1c` bytes before the heap/stack reservation.

7. `Reset_Handler` calls `__libc_init_array`.
   - This runs C/C++ initialization hooks and constructors.
   - In this C-only skeleton, there are no application constructors.

8. `Reset_Handler` calls `main`.
   - Source: `Core/Src/main.c`.

9. `main()` enters an empty infinite loop.

10. If `main()` ever returns, `Reset_Handler` falls into `LoopForever`.
    - Current `main()` does not return.

Boot call graph:

```text
CPU reset
`-- g_pfnVectors
    |-- initial MSP = _estack
    `-- Reset_Handler
        |-- SystemInit          [weak, no implementation currently linked]
        |-- copy .data          [currently empty]
        |-- zero .bss           [currently 0x1c bytes]
        |-- __libc_init_array
        `-- main
            `-- while (1)
```

## 4. Runtime Flow

Runtime behavior:

```text
main()
`-- while (1)
    `-- do nothing forever
```

There is no scheduler:

- No RTOS.
- No cooperative task dispatcher.
- No timer tick handler.
- No event queue.
- No low-power wait instruction such as `WFI`.
- No watchdog refresh.

Initialization flow by peripheral/module:

| Peripheral/module | Init function | Where called | Dependencies | Current status |
| --- | --- | --- | --- | --- |
| Core clock/system | `SystemInit` | Intended from `Reset_Handler` | CMSIS system file normally provides it. | Missing implementation. |
| HAL | `HAL_Init` | Nowhere | HAL sources/headers. | Missing. |
| System clock config | `SystemClock_Config` | Nowhere | RCC/HAL or CMSIS. | Missing. |
| GPIO | Usually `MX_GPIO_Init` | Nowhere | HAL GPIO driver. | Missing. |
| UART/SPI/I2C/ADC/TIM/DMA | Usually `MX_*_Init` | Nowhere | HAL drivers and pin config. | Missing. |
| SysTick | Usually configured by HAL or CMSIS | Nowhere in current source | SysTick registers and handler. | Not configured by app. |
| Heap | `_sbrk` | Only if `malloc` or libc allocation is linked | Linker symbols. | Source present; not used by current app. |
| Syscalls | `_read`, `_write`, etc. | Only if libc paths reference them | Optional `__io_putchar/getchar`. | Source present; not used by current app. |

Order dependencies:

- Stack pointer must be valid before any C or function-call code runs.
- `.data` and `.bss` must be initialized before C code uses globals/statics.
- `__libc_init_array` must run before C++ constructors or libc init hooks are needed.
- Peripheral init would normally run after C runtime init, inside `main()`, but no such code exists yet.

Why order matters:

- If `_estack` points outside SRAM, the CPU can fault before reaching `main()`.
- If `.bss` is not zeroed, static variables start with garbage.
- If clocks and peripheral buses are not enabled before touching peripherals, register accesses may not work as intended.

## 5. Data Flow

Current firmware has no application data flow. There are no sensor samples, communication packets, commands, configuration records, queues, or persistent data structures.

Existing low-level data flows:

### Boot-time `.data` initialization

```text
Flash load address _sidata
-> Reset_Handler copy loop
-> RAM range [_sdata, _edata)
-> globals with nonzero initializers
```

Current status: `.data` size is `0`, so no initialized global data is copied.

### Boot-time `.bss` initialization

```text
RAM range [_sbss, _ebss)
-> Reset_Handler zero-fill loop
-> globals/statics with zero initialization
```

Current status: `.bss` size is `0x1c` bytes before the reserved heap/stack block. This is C runtime data, not application state.

### Heap allocation path, if used later

```text
malloc/newlib allocator
-> _sbrk(incr) in Core/Src/sysmem.c
-> __sbrk_heap_end grows from _end
-> rejects growth beyond (_estack - _Min_Stack_Size)
-> returns block or (void *)-1 with errno = ENOMEM
```

Current status: no current application code calls `malloc()`, so `_sbrk()` is not part of the active runtime path.

### Character I/O path, if used later

```text
printf/libc write path
-> _write()
-> __io_putchar()
-> target-specific output device
```

```text
scanf/libc read path
-> _read()
-> __io_getchar()
-> target-specific input device
```

Current status: no `__io_putchar()` or `__io_getchar()` implementation exists in the current tree. There is no UART, SWO, USB, or semihosting binding.

Application data flow requested but absent:

| Flow | Current finding |
| --- | --- |
| Sensor data | No sensor drivers or read functions. |
| Communication packets | No encoder/decoder, buffers, radio, UART protocol, CAN, Modbus, BLE, LoRa, or LoRaWAN code. |
| Commands | No command parser or dispatch table. |
| Configuration data | No config structs or config load/save path. |
| NVM/EEPROM/Flash storage | No flash driver calls or reserved storage pages. |
| Buffers and queues | No application buffers or queues. |

## 6. Interrupt Map

The vector table is defined in `startup_stm32f103xb.s` as `g_pfnVectors`. Every non-reserved exception/interrupt handler is weakly aliased to `Default_Handler` unless another source file defines the same symbol. No such overriding source file exists in the current tree.

`Default_Handler` behavior:

```text
Default_Handler
`-- Infinite_Loop
    `-- branch to self forever
```

Shared state changed by interrupts: none.

Race conditions found: none in the current application, because no interrupt updates shared variables. The practical risk is different: any unexpectedly enabled interrupt traps the CPU forever in `Default_Handler`.

Cortex exception entries:

| Vector | Current ISR | Trigger source | Current effect |
| --- | --- | --- | --- |
| NMI | `NMI_Handler -> Default_Handler` | Non-maskable interrupt | Infinite loop. |
| HardFault | `HardFault_Handler -> Default_Handler` | Fault | Infinite loop. |
| MemManage | `MemManage_Handler -> Default_Handler` | MPU/memory fault | Infinite loop. |
| BusFault | `BusFault_Handler -> Default_Handler` | Bus fault | Infinite loop. |
| UsageFault | `UsageFault_Handler -> Default_Handler` | Undefined instruction/state fault | Infinite loop. |
| SVC | `SVC_Handler -> Default_Handler` | Supervisor call | Infinite loop. |
| DebugMon | `DebugMon_Handler -> Default_Handler` | Debug monitor | Infinite loop. |
| PendSV | `PendSV_Handler -> Default_Handler` | Pendable service exception | Infinite loop. |
| SysTick | `SysTick_Handler -> Default_Handler` | SysTick timer | Infinite loop if SysTick is enabled. |

STM32 peripheral interrupt entries:

All of the following map to `Default_Handler` in the current firmware:

```text
WWDG_IRQHandler
PVD_IRQHandler
TAMPER_IRQHandler
RTC_IRQHandler
FLASH_IRQHandler
RCC_IRQHandler
EXTI0_IRQHandler
EXTI1_IRQHandler
EXTI2_IRQHandler
EXTI3_IRQHandler
EXTI4_IRQHandler
DMA1_Channel1_IRQHandler
DMA1_Channel2_IRQHandler
DMA1_Channel3_IRQHandler
DMA1_Channel4_IRQHandler
DMA1_Channel5_IRQHandler
DMA1_Channel6_IRQHandler
DMA1_Channel7_IRQHandler
ADC1_2_IRQHandler
USB_HP_CAN_TX_IRQHandler
USB_LP_CAN_RX0_IRQHandler
CAN_RX1_IRQHandler
CAN_SCE_IRQHandler
EXTI9_5_IRQHandler
TIM1_BRK_IRQHandler
TIM1_UP_IRQHandler
TIM1_TRG_COM_IRQHandler
TIM1_CC_IRQHandler
TIM2_IRQHandler
TIM3_IRQHandler
TIM4_IRQHandler
I2C1_EV_IRQHandler
I2C1_ER_IRQHandler
I2C2_EV_IRQHandler
I2C2_ER_IRQHandler
SPI1_IRQHandler
SPI2_IRQHandler
USART1_IRQHandler
USART2_IRQHandler
USART3_IRQHandler
EXTI15_10_IRQHandler
RTCAlarm_IRQHandler
TIM8_BRK_IRQHandler
TIM8_UP_IRQHandler
TIM8_TRG_COM_IRQHandler
TIM8_CC_IRQHandler
ADC3_IRQHandler
FSMC_IRQHandler
SDIO_IRQHandler
TIM5_IRQHandler
SPI3_IRQHandler
UART4_IRQHandler
UART5_IRQHandler
TIM6_IRQHandler
TIM7_IRQHandler
DMA2_Channel1_IRQHandler
DMA2_Channel2_IRQHandler
DMA2_Channel3_IRQHandler
DMA2_Channel4_5_IRQHandler
```

Important interrupt implications:

- There is no `Core/Src/stm32f1xx_it.c`.
- There are no HAL callback handlers.
- There are no DMA callbacks.
- There are no UART/SPI/I2C interrupt receive/transmit handlers.
- If future code enables a peripheral interrupt before implementing its handler, the firmware will appear to hang.

## 7. Risks / Bugs

High-priority findings:

1. Missing generated runtime/HAL files
   - `.mxproject` references files such as `Core/Src/system_stm32f1xx.c`, `Core/Src/stm32f1xx_it.c`, `Core/Src/stm32f1xx_hal_msp.c`, HAL drivers, CMSIS headers, and `Core/Inc/*.h`.
   - These files are absent from the current tree.
   - Result: no real `SystemInit`, no HAL, no peripheral init, and no interrupt source file.

2. Target metadata mismatch
   - `bluepill.ioc` names an STM32F103C8 target.
   - `Makefile`, linker script, VS Code debug config, and repair guide target STM32F103C6-class memory.
   - The repair guide says this was intentional after hardware probing showed 32 KB flash and 10 KB RAM.
   - Keep this distinction explicit. Regenerating from CubeMX could accidentally restore a larger C8 memory map and reintroduce an invalid stack pointer on the actual board.

3. No active system clock setup
   - `Reset_Handler` references `SystemInit`, but no implementation is in the current source tree.
   - The MCU will remain close to reset/default clock configuration unless hardware/debugger state changes it.
   - Any timing assumptions should be treated as invalid until a real system file and clock config are restored.

4. All interrupts trap forever
   - Every handler maps to `Default_Handler`.
   - This is useful for early bring-up, but unsafe once SysTick or peripherals are enabled.

5. Empty runtime loop burns CPU
   - `main()` is an empty `while (1)` loop.
   - It does no useful work and does not enter sleep.

6. Syscall I/O is not retargeted
   - `_write()` calls weak `__io_putchar()`.
   - `_read()` calls weak `__io_getchar()`.
   - No implementations exist. If stdio paths are used later, add a real UART/SWO/semihosting backend or guard these calls.

7. Heap and stack policy is minimal
   - `_Min_Stack_Size` is 1 KB.
   - `_sbrk()` only protects that reserved stack region if malloc is linked.
   - There is no stack watermarking, overflow detection, or heap usage telemetry.

8. Build config has stale HAL intent
   - `Makefile` defines `USE_HAL_DRIVER`, but no HAL headers/sources are present.
   - `-ICore/Inc` points to a missing directory.
   - This is harmless while nothing includes HAL headers, but confusing during future development.

Code quality review:

- Tight coupling: startup depends on standard linker symbols; this is normal for embedded startup code.
- Hidden dependencies: `SystemInit`, `__io_putchar`, and `__io_getchar` are weak/external dependencies with no current implementation.
- Magic numbers: memory sizes `32K`, `10K`, heap `0x200`, and stack `0x400` are intentional but should stay tied to hardware evidence.
- Duplicate logic: none in the current application.
- Naming issues: `startup_stm32f103xb.s` filename suggests xB, while comments/debug config target C6; document this carefully to avoid wrong part selection.
- Potential overflow: no application buffers exist; future risk is heap/stack collision or invalid retargeted I/O calls.

State machine analysis:

- No explicit state machine exists.
- No `enum` states, `switch`-based transition logic, event queue, or task states were found.
- The only implicit lifecycle is:

```text
Reset -> C runtime init -> main idle loop
Fault/interrupt -> Default_Handler infinite loop
```

Memory usage:

| Item | Current value | Source |
| --- | --- | --- |
| Flash origin/length | `0x08000000`, `32K` | `STM32F103XX_FLASH.ld` |
| RAM origin/length | `0x20000000`, `10K` | `STM32F103XX_FLASH.ld` |
| Initial MSP / `_estack` | `0x20002800` | linker script and ELF symbols |
| Minimum heap reservation | `0x200` bytes | linker script |
| Minimum stack reservation | `0x400` bytes | linker script |
| `.isr_vector` | `0x130` bytes | ELF section table / map |
| `.text` | `0x14c` bytes | ELF section table / map |
| `.data` | `0` bytes | ELF section table / map |
| `.bss` | `0x1c` bytes | ELF section table / map |
| `._user_heap_stack` | `0x604` bytes | ELF section table / map |
| Effective size-style RAM use | `1568` bytes | `.bss + ._user_heap_stack` |

Driver analysis:

- No hardware drivers are present.
- No APIs exist for init/read/write/error handling.
- No peripheral handles exist.
- No HAL MSP file exists to bind GPIO pins, clocks, DMA channels, or NVIC priorities.

Communication protocol analysis:

- No UART packet protocol.
- No BLE.
- No LoRa/LoRaWAN.
- No Modbus.
- No CAN.
- No custom binary packets.
- No protobuf.
- No CRC/checksum logic.

Persistent storage:

- No flash layout beyond code/data sections.
- No EEPROM emulation.
- No stored structs.
- No wear leveling.
- No versioning.
- No recovery logic after power loss.

Concurrency and timing:

- Single-threaded bare-metal loop.
- No tasks or threads.
- No RTOS.
- No active interrupt-driven concurrency.
- No blocking peripheral calls.
- No delay functions.
- No watchdog.

Error handling:

- Unexpected interrupts/exceptions enter `Default_Handler` forever.
- `_exit()` calls `_kill()` and loops forever.
- Several syscall stubs return `-1` and sometimes set `errno`.
- No application `Error_Handler()`.
- HAL assert is disabled in `bluepill.ioc`.
- No retry logic or fail-safe state exists.

## 8. Recommended Reading Order

For a junior engineer learning this codebase, read in this order:

1. `README.md`
   - Tiny, but confirms the project identity.

2. `BLUEPILL_JLINK_DEBUG_REPAIR_GUIDE.md`
   - Explains the real hardware bring-up problem: stack pointer was previously outside valid SRAM.
   - This gives essential context for why the linker targets 10 KB RAM.

3. `Makefile`
   - Shows exactly what source files are compiled.
   - Confirms Cortex-M3, `STM32F103x6`, `nano.specs`, linker script, and map generation.

4. `STM32F103XX_FLASH.ld`
   - Understand memory layout before reading startup code.
   - Focus on `_estack`, `MEMORY`, `.isr_vector`, `.data`, `.bss`, and `._user_heap_stack`.

5. `startup_stm32f103xb.s`
   - Read `Reset_Handler` first.
   - Then read `g_pfnVectors`.
   - Then read the weak aliases to `Default_Handler`.

6. `Core/Src/main.c`
   - This is currently short because the application has not been implemented.

7. `Core/Src/sysmem.c`
   - Read `_sbrk()` to understand future heap behavior if `malloc()` is introduced.

8. `Core/Src/syscalls.c`
   - Read `_write()`, `_read()`, and `_exit()`.
   - Treat these as C library plumbing, not application protocol code.

9. `bluepill.ioc` and `.mxproject`
   - Read these last as historical/generated metadata.
   - They reference missing files and an STM32F103C8 configuration, so do not assume they match the build.

10. `.vscode/tasks.json` and `.vscode/launch.json`
    - Useful for build/flash/debug workflow.
    - The embedded config is `Build + Flash + Debug Blue Pill`.

Critical functions/symbols to know:

- `Reset_Handler`
- `Default_Handler`
- `g_pfnVectors`
- `main`
- `_sbrk`
- `_read`
- `_write`
- `_estack`
- `_sdata`, `_edata`, `_sidata`
- `_sbss`, `_ebss`
- `_Min_Heap_Size`, `_Min_Stack_Size`

Important sequence diagrams:

Boot sequence:

```text
CPU reset
-> read MSP from vector[0]
-> read PC from vector[1]
-> Reset_Handler
-> set SP = _estack
-> SystemInit [not implemented in current tree]
-> copy .data
-> zero .bss
-> __libc_init_array
-> main
-> empty while(1)
```

Unexpected interrupt sequence:

```text
Peripheral or exception event
-> NVIC vector lookup
-> weak IRQ handler
-> Default_Handler
-> infinite loop
```

Future heap allocation sequence:

```text
Application calls malloc()
-> newlib allocator calls _sbrk(incr)
-> _sbrk starts from _end
-> _sbrk checks against _estack - _Min_Stack_Size
-> returns memory or ENOMEM
```

What to document next when real application code is added:

- Add a module table for each driver and subsystem.
- Add init order with exact function calls from `main()`.
- Add interrupt ownership as soon as `stm32f1xx_it.c` or HAL callbacks appear.
- Add data-flow diagrams for each sensor, packet, command, and storage path.
- Add memory tables for every global/static buffer larger than a few dozen bytes.
- Add state-machine diagrams when enums or event-driven transitions are introduced.
