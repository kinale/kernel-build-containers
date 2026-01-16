#!/usr/bin/env bash
set -eu

DELIMITER="echo -e \n##############################################"

ARCHS=("x86_64" "i386" "arm64" "arm" "riscv" "powerpc" "powerpc64" "powerpc64le")
COMPILERS=("gcc-13" "clang-15")
RUNTIME_FLAG=""

SRC_DIR=$PWD/linux-sources
OUT_DIR=$PWD/build_out
SRC_TARBALL=$PWD/linux-sources.tar.xz
KERNEL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.65.tar.xz"
EXPECTED_HASH="54e852667af35c0ed06cfc81311e65fa7f5f798a3bfcf78a559d3b4785a139c1"

declare -A EXPECTED_IMAGES=(
	[x86_64]="arch/x86/boot/bzImage"
	[i386]="arch/x86/boot/bzImage"
	[arm64]="arch/arm64/boot/Image.gz"
	[arm]="arch/arm/boot/zImage"
	[riscv]="arch/riscv/boot/Image.gz"
	[powerpc]="arch/powerpc/boot/zImage"
	[powerpc64]="arch/powerpc/boot/zImage"
	[powerpc64le]="arch/powerpc/boot/zImage"
)

fail() { echo "[-] $*"; exit 1; }

prepare_deps(){
	echo "Preparing dependencies..."

	for cmd in wget tar expect; do
		if [ -z "$(command -v "$cmd")" ]; then
			fail "Make sure these utilities are installed: wget tar expect"
		fi
	done

	if [ -f "$SRC_TARBALL" ]; then
		CALCULATED_HASH=$(sha256sum "$SRC_TARBALL" | awk '{print $1}')
		if [ "$CALCULATED_HASH" = "$EXPECTED_HASH" ]; then
			echo "Using existing $SRC_TARBALL (hash verified)"
		else
			fail "$SRC_TARBALL exists but hash does not match. Remove $SRC_TARBALL manually to re-download."
		fi
	else
		wget "$KERNEL" -O "$SRC_TARBALL"
	fi

	if [ -e "$SRC_DIR" ] || [ -e "$OUT_DIR" ]; then
		fail "Working directory is not clean! Remove $SRC_DIR $OUT_DIR"
	fi


	mkdir -p $SRC_DIR $OUT_DIR
	tar -xf $SRC_TARBALL -C $SRC_DIR --strip-components=1
}

prepare_compilers(){
	$DELIMITER
	echo "Preparing compilers..."
	for compiler in "${COMPILERS[@]}"; do
		python3 manage_images.py $RUNTIME_FLAG -b $compiler
	done
}

run_tests(){
	prepare_compilers

	$DELIMITER
	echo "Testing kernel building..."
	for arch in "${ARCHS[@]}"; do
		for compiler in "${COMPILERS[@]}"; do
			cfg="${OUT_DIR}/${arch}__${compiler}/.config"
			[[ -e "$cfg" ]] && fail "Unexpected .config: $cfg"

			python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "$arch" -c "$compiler" -s "$SRC_DIR" -o "$OUT_DIR" -- defconfig
			[[ -f "$cfg" ]] || fail "Missing .config after defconfig: $cfg"

			python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "$arch" -c "$compiler" -s "$SRC_DIR" -o "$OUT_DIR"
			expected="${OUT_DIR}/${arch}__${compiler}/${EXPECTED_IMAGES[$arch]}"
			[[ -f "$expected" ]] || fail "Missing expected image after full build: $expected"

			python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "$arch" -c "$compiler" -s "$SRC_DIR" -o "$OUT_DIR" -- mrproper
		done
	done
}

cleanup(){
	if [ -e "$SRC_TARBALL" ] && [ -e "$SRC_DIR" ] && [ -e "$OUT_DIR" ]; then
		echo "It is safe to remove these directories: $SRC_TARBALL $SRC_DIR $OUT_DIR"
	fi
}

echo "Let's test build_linux.py..."
prepare_deps
python3 -m coverage erase

# Test Docker as a default container runtime (without a flag)
RUNTIME_FLAG=""
run_tests

# Test Docker
RUNTIME_FLAG="-d"
run_tests

# Test Podman
RUNTIME_FLAG="-p"
run_tests

echo "All tests completed. Creating the coverage report..."
python3 -m coverage report
python3 -m coverage html
cleanup
echo "Well done!"
