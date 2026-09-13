cmake_minimum_required(VERSION 3.16)

# ---------------------------------------------------------------------------
# freeBOOT - Xbox 360 (Xenon / PowerPC 64-bit big-endian) bootloader
#
# Toolchain preference order:
#   1. xenon-gcc / xenon-as / xenon-objcopy   (libxenon / devkitXenon)
#   2. powerpc64-linux-gnu-gcc -mbig-endian   (generic ppc64be cross-gcc)
#
# Usage:
#   cmake -B build && cmake --build build
#
# Override toolchain prefix at configure time if needed:
#   cmake -B build -DXENON_PREFIX=powerpc64-linux-gnu-
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Toolchain detection - must happen BEFORE project()
# ---------------------------------------------------------------------------

# Allow the user to pin a prefix explicitly.
set(XENON_PREFIX "" CACHE STRING
    "Cross-compiler prefix (e.g. 'xenon-' or 'powerpc64-linux-gnu-'). \
     Leave empty for auto-detection.")

if(NOT XENON_PREFIX)
    # Try the real Xenon toolchain first.
    find_program(_XENON_GCC xenon-gcc)
    if(_XENON_GCC)
        set(XENON_PREFIX "xenon-")
        set(_XENON_NATIVE TRUE)
        message(STATUS "freeBOOT: found xenon-gcc, using xenon- toolchain")
    else()
        # Fall back to a generic ppc64be cross-gcc.
        foreach(_TRY IN ITEMS
                powerpc64-linux-gnu-gcc
                powerpc64-unknown-linux-gnu-gcc
                ppc64-linux-gnu-gcc)
            find_program(_FALLBACK_GCC ${_TRY})
            if(_FALLBACK_GCC)
                string(REGEX REPLACE "gcc$" "" XENON_PREFIX "${_TRY}")
                set(_XENON_NATIVE FALSE)
                message(STATUS "freeBOOT: xenon-gcc not found - falling back to ${_TRY}")
                break()
            endif()
        endforeach()
        if(NOT _FALLBACK_GCC)
            message(FATAL_ERROR
                "freeBOOT: No suitable cross-compiler found.\n"
                "Install devkitXenon (xenon-gcc) or a ppc64be cross-GCC "
                "(e.g. powerpc64-linux-gnu-gcc) and make sure it is on PATH.")
        endif()
    endif()
endif()

# Resolve tool names from the chosen prefix.
set(CMAKE_C_COMPILER   "${XENON_PREFIX}gcc")
set(CMAKE_ASM_COMPILER "${XENON_PREFIX}gcc") # use gcc as assembler driver
set(CMAKE_LINKER       "${XENON_PREFIX}gcc")

# Skip the compiler sanity-check (we are cross-compiling to bare-metal).
set(CMAKE_C_COMPILER_WORKS   TRUE CACHE BOOL "" FORCE)
set(CMAKE_ASM_COMPILER_WORKS TRUE CACHE BOOL "" FORCE)

project(freeBOOT C ASM)

# ---------------------------------------------------------------------------
# Target CPU flags
# ---------------------------------------------------------------------------

# The Xenon is a PowerPC 970MP derivative: 64-bit, big-endian, VMX (Altivec).
# With the native xenon-gcc the defaults are already correct; we still set
# them explicitly so the build is self-documenting.
set(ARCH_FLAGS
    -m64
    -mbig-endian
    -mhard-float
    -maltivec
)

# ---------------------------------------------------------------------------
# Common compiler / assembler flags
# ---------------------------------------------------------------------------

set(COMMON_FLAGS
    ${ARCH_FLAGS}
    -ffreestanding          # No hosted libc/startup
    -fno-builtin            # Do not substitute builtins
    -fno-stack-protector    # No SSP - no libc
    -fno-common             # Strict linkage
    -nostdlib               # Do not link standard libs
    -nostdinc               # Do not search host include dirs
    -O2
    -Wall
    -Wextra
)

set(C_ONLY_FLAGS
    -std=gnu99
)

# ---------------------------------------------------------------------------
# Linker flags
# ---------------------------------------------------------------------------

set(LINKER_SCRIPT "${CMAKE_SOURCE_DIR}/reboot.lds")

set(LINK_FLAGS
    ${ARCH_FLAGS}
    -nostdlib
    -static
    -Wl,--nmagic
    -Wl,-T,${LINKER_SCRIPT}
    -Wl,--gc-sections
)

# ---------------------------------------------------------------------------
# Sources
#
# asm/startup2.S MUST be listed first so _start lands at the beginning of .text.
# asm/payload.S is NOT included here: it is a standalone binary blob whose
# pre-assembled output is already checked in as include/payload.h.
# It has its own _start and would cause a duplicate-symbol link error.
set(ASM_SOURCES
    asm/startup2.S
    asm/cache.S
)

set(C_SOURCES
    src/main.c
)

# ---------------------------------------------------------------------------
# Build the ELF executable
# ---------------------------------------------------------------------------

add_executable(freeboot.elf
    ${ASM_SOURCES}
    ${C_SOURCES}
)

target_include_directories(freeboot.elf PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

target_compile_options(freeboot.elf PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${COMMON_FLAGS} ${C_ONLY_FLAGS}>
    $<$<COMPILE_LANGUAGE:ASM>:${COMMON_FLAGS}>
)

# CMake requires LINK_FLAGS as a space-separated string.
list(JOIN LINK_FLAGS " " LINK_FLAGS_STR)
set_target_properties(freeboot.elf PROPERTIES
    LINK_FLAGS "${LINK_FLAGS_STR}"
    LINK_DEPENDS "${LINKER_SCRIPT}"
)

# ---------------------------------------------------------------------------
# Strip & produce final raw binary via objcopy
# ---------------------------------------------------------------------------

find_program(OBJCOPY_TOOL
    NAMES "${XENON_PREFIX}objcopy" objcopy
    REQUIRED
)

set(BIN_OUTPUT "${CMAKE_BINARY_DIR}/freeboot.bin")

add_custom_command(
    OUTPUT  ${BIN_OUTPUT}
    COMMAND ${OBJCOPY_TOOL}
            -O binary
            -S
            --gap-fill 0x00
            $<TARGET_FILE:freeboot.elf>
            ${BIN_OUTPUT}
    DEPENDS freeboot.elf
    COMMENT "objcopy: ELF -> freeboot.bin"
    VERBATIM
)

add_custom_target(freeboot ALL
    DEPENDS ${BIN_OUTPUT}
    COMMENT "freeBOOT binary ready: ${BIN_OUTPUT}"
)

# ---------------------------------------------------------------------------
# Optional: size report after each build
# ---------------------------------------------------------------------------

find_program(SIZE_TOOL NAMES "${XENON_PREFIX}size" size)

if(SIZE_TOOL)
    add_custom_command(TARGET freeboot POST_BUILD
        COMMAND ${SIZE_TOOL} $<TARGET_FILE:freeboot.elf>
        COMMENT "Section sizes:"
        VERBATIM
    )
endif()

# ---------------------------------------------------------------------------
# Install / convenience targets
# ---------------------------------------------------------------------------

# cmake --install build  ->  copies freeboot.bin to <prefix>/bin/
install(FILES ${BIN_OUTPUT} DESTINATION bin)

# cmake --build build --target bin  (alias)
add_custom_target(bin DEPENDS ${BIN_OUTPUT})

# ---------------------------------------------------------------------------
# Build summary
# ---------------------------------------------------------------------------
message(STATUS "  Toolchain prefix : ${XENON_PREFIX}")
message(STATUS "  C compiler       : ${CMAKE_C_COMPILER}")
message(STATUS "  Assembler        : ${CMAKE_ASM_COMPILER}")
message(STATUS "  objcopy          : ${OBJCOPY_TOOL}")
message(STATUS "  Linker script    : ${LINKER_SCRIPT}")
message(STATUS "  Output ELF       : ${CMAKE_BINARY_DIR}/freeboot.elf")
message(STATUS "  Output BIN       : ${BIN_OUTPUT}")
