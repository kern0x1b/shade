# Guest regression tests

Small armv7 programs that run inside the emulated device and check what only a
running guest shows: signal frames and fault delivery (`signals.c`), stale
translations after images are swapped or protections change (`remap.c`,
`remap_image.c`), and code rewritten through a second view of a page or from a
signal handler (`smc.c`). `longrun.c` stays for a given number of seconds, for
looking at what the rest of a boot does meanwhile.

Each prints one line per check and exits with the number of failures.

    CC="clang -target armv7-apple-ios5.0 -miphoneos-version-min=5.0 -isysroot <iPhoneOS SDK>"
    $CC -mthumb -o signals signals.c
    $CC -o smc smc.c
    $CC -o remap remap.c
    $CC -dynamiclib -DIMAGE_VALUE=1 -install_name /usr/local/lib/charon-remap-1.dylib -o charon-remap-1.dylib remap_image.c
    $CC -dynamiclib -DIMAGE_VALUE=2 -install_name /usr/local/lib/charon-remap-2.dylib -o charon-remap-2.dylib remap_image.c

Sign the results (ldid -S), put them in the rootfs of the device to boot, and
run them there as the test program of a boot; the install paths `remap.c` opens
are the `-install_name` values above.
