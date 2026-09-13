cmake_minimum_required(VERSION 3.16)

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

set(CMAKE_C_COMPILER   "${XENON_PREFIX}gcc")
set(CMAKE_ASM_COMPILER "${XENON_PREFIX}gcc")
set(CMAKE_LINKER       "${XENON_PREFIX}gcc")

set(CMAKE_C_COMPILER_WORKS   TRUE CACHE BOOL "" FORCE)
set(CMAKE_ASM_COMPILER_WORKS TRUE CACHE BOOL "" FORCE)

project(freeBOOT C ASM)

# PowerPC 970MP, 64-bit, big-endian, VMX 
set(ARCH_FLAGS
    -m64
    -mbig-endian
    -mhard-float
    -maltivec
)

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


set(LINKER_SCRIPT "${CMAKE_SOURCE_DIR}/reboot.lds")

set(LINK_FLAGS
    ${ARCH_FLAGS}
    -nostdlib
    -static
    -Wl,--nmagic
    -Wl,-T,${LINKER_SCRIPT}
    -Wl,--gc-sections
)

set(ASM_SOURCES
    asm/startup2.S
    asm/cache.S
)

set(C_SOURCES
    src/main.c
)

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

find_program(SIZE_TOOL NAMES "${XENON_PREFIX}size" size)

if(SIZE_TOOL)
    add_custom_command(TARGET freeboot POST_BUILD
        COMMAND ${SIZE_TOOL} $<TARGET_FILE:freeboot.elf>
        COMMENT "Section sizes:"
        VERBATIM
    )
endif()

install(FILES ${BIN_OUTPUT} DESTINATION bin)

add_custom_target(bin DEPENDS ${BIN_OUTPUT})

message(STATUS "  Toolchain prefix : ${XENON_PREFIX}")
message(STATUS "  C compiler       : ${CMAKE_C_COMPILER}")
message(STATUS "  Assembler        : ${CMAKE_ASM_COMPILER}")
message(STATUS "  objcopy          : ${OBJCOPY_TOOL}")
message(STATUS "  Linker script    : ${LINKER_SCRIPT}")
message(STATUS "  Output ELF       : ${CMAKE_BINARY_DIR}/freeboot.elf")
message(STATUS "  Output BIN       : ${BIN_OUTPUT}")
