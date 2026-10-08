#!/bin/sh
set -eu
if [ "${PLATFORM_NAME}" != "macosx" ]; then exit 0; fi
cli_output="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/formi"
cli_work="${DERIVED_FILE_DIR}/formi-cli"
mkdir -p "$(dirname "$cli_output")" "$cli_work/cache"
for cli_arch in $ARCHS; do
    set --
    if [ "$CONFIGURATION" = "Debug" ]; then set -- -D DEBUG; fi
    /usr/bin/xcrun swiftc -parse-as-library -swift-version 6 -O \
        "$@" \
        -sdk "$SDKROOT" -target "${cli_arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" \
        -module-cache-path "$cli_work/cache" \
        "$SRCROOT/Tools/FormiCLI/FormiCLI.swift" \
        "$SRCROOT/Packages/FinanceCore/Sources/FinanceCore/Services/FormiCLIProtocol.swift" \
        "$SRCROOT/Packages/FinanceCore/Sources/FinanceCore/Services/FormiCLIArguments.swift" \
        -o "$cli_work/formi-$cli_arch"
done
# Xcode architecture names contain no shell metacharacters; preserve paths with spaces.
set --
for cli_arch in $ARCHS; do set -- "$@" "$cli_work/formi-$cli_arch"; done
/usr/bin/xcrun lipo -create "$@" -output "$cli_output"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
    /usr/bin/codesign --force --options runtime \
        --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$cli_output"
fi
