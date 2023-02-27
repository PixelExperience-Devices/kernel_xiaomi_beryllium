#! /bin/bash
# Copyright (C) 2020 KenHV
# Copyright (C) 2020 Starlight
# Copyright (C) 2021 CloudedQuartz
# Copyright (C) 2023 PaperBoy

# Config
DEVICE="beryllium"
DEFCONFIG="${DEVICE}_defconfig"
LOG="$HOME/log.log"

# Export arch and subarch
ARCH="arm64"
SUBARCH="arm64"
export ARCH SUBARCH
export KBUILD_BUILD_USER="PaperBoy"

KERNEL_IMG=$KERNEL_DIR/out/arch/$ARCH/boot/Image.gz-dtb

TG_CHAT_ID="$CHANNEL_ID"
TG_BOT_TOKEN="$BOT_API_KEY"
# End config

# Function definitions

# Status message function
msg() {
	echo
	echo -e "\e[1;32m$*\e[0m"
	echo
}

# tg_sendinfo - sends text through telegram
tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
		-F parse_mode=html \
		-F text="${1}" \
		-F chat_id="${TG_CHAT_ID}" &> /dev/null
}

# tg_pushzip - uploads final zip to telegram
tg_pushzip() {
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)
	curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
			-F chat_id=$TG_CHAT_ID \
			-F caption="$2 | <b>MD5 Checksum : </b><code>$MD5CHECK</code>" \
			-F parse_mode=html &> /dev/null
}

# tg_failed - uploads build log to telegram
tg_failed() {
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html &> /dev/null
}

# build_setup - enter kernel directory and get info for caption.
# also removes the previous kernel image, if one exists.
build_setup() {
    cd "$KERNEL_DIR" || echo -e "\nKernel directory ($KERNEL_DIR) does not exist" || exit 1

    [[ ! -d out ]] && mkdir out
    [[ -f "$KERNEL_IMG" ]] && rm "$KERNEL_IMG"
	find . -name "*.dtb" -type f -delete
}

# build_config - builds .config file for device.
build_config() {
	make O=out $1 -j$(nproc --all)
}
# build_kernel - builds defconfig and kernel image using llvm tools, while saving the output to a specified log location
# only use after runing build_setup()
build_kernel() {

    msg "|| Start Building ||"
    make O=out $DEFCONFIG -j$(nproc --all)
    BUILD_START=$(date +"%s")
	echo $TC_DIR
    make -j$(nproc --all) O=out \
                PATH="$TC_DIR/bin:$PATH" \
                CC="clang" \
                CROSS_COMPILE=$TC_DIR/bin/aarch64-linux-gnu- \
                CROSS_COMPILE_ARM32=$TC_DIR/bin/arm-linux-gnueabi- \
                LLVM=llvm- \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip |& tee $LOG

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
}

LINUXVER=$(make kernelversion)
KBUILD_COMPILER_STRING=$("$TC_DIR"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

# build_end - creates and sends zip
build_end() {

	if ! [ -a "$KERNEL_IMG" ]; then
        echo -e "\n"
        msg "|| Build Failed, Sending logs to telegram ||"
        tg_failed
        tg_buildtime
        exit 1
    fi

    echo -e "\n"
    msg "|| Build Completed ||"
	cd "$AK_DIR" || echo -e "\nAnykernel directory ($AK_DIR) does not exist" || exit 1
	git clean -fd
	mv "$KERNEL_IMG" "$AK_DIR"/zImage
	ZIP_NAME=$KERNELNAME-$1-$COMMIT_SHA-$(date +%Y-%m-%d_%H%M)-UTC
	zip -r9 "$ZIP_NAME".zip ./* -x .git README.md ./*placeholder

	ZIP_NAME="$ZIP_NAME.zip"

    tg_pushzip "$ZIP_NAME" "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
	echo -e "\n> Sent zip through Telegram.\n> File: $ZIP_NAME"
}

# End function definitions

COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
DISTRO=$(source /etc/os-release && echo "${NAME}")
PROCS=$(nproc --all)

CAPTION=$(echo -e \
"\n\nHEAD: <code>$COMMIT_SHA: </code><code>$COMMIT</code>
\n\nBranch: <code>$KERNEL_BRANCH</code>
\n\nLinux Version: <code>$LINUXVER</code>
\n\nCompiler info: <code>$KBUILD_COMPILER_STRING</code>
\n\nDocker OS: <code>$DISTRO</code>
\n\nHost Core Count : <code>$PROCS</code>")

tg_sendinfo "-- Gayming Karnul Build Triggered --
$CAPTION"

# Build for device 1
echo -e "\n"
msg "|| Building for Beryllium ||"
build_setup $DEFCONFIG
build_kernel
build_end $DEVICE

# Build old touch fw version for device 1
build_setup
git apply old_touch_fw.patch
build_config $DEFCONFIG
build_kernel
build_end ${DEVICE}_old_touch_fw

# Build NON SE version for device 1
build_setup
git apply non_se.patch
build_config $DEFCONFIG
build_kernel
build_end ${DEVICE}_non_SE

# Build MIUI NSE version for device 1
build_setup
git apply non_se.patch
git apply miui_rom.patch
build_config $DEFCONFIG
build_kernel
build_end ${DEVICE}_miui_version_NSE

echo -e "\n"
msg "|| All jobs done. Proceeding to post compilation works.. ||"
