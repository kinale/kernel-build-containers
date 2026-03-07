#!/usr/bin/env bash
set -eu

DELIMITER="\n##############################################"

ARCHS=("x86_64" "i386" "arm64" "arm" "riscv" "powerpc" "powerpc64" "powerpc64le")
COMPILERS=("gcc-13" "clang-15")
RUNTIME_FLAG=""

SRC_DIR="$PWD/linux_src"
OUT_DIR="$PWD/build_out"
SRC_TARBALL="$PWD/linux_src.tar.xz"
KERNEL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.65.tar.xz"
EXPECTED_CHECKSUM="54e852667af35c0ed06cfc81311e65fa7f5f798a3bfcf78a559d3b4785a139c1"

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

fail() {
	echo "[-] $*"
	exit 1
}

prepare_tests() {
	echo -e $DELIMITER
	echo "Preparing to the tests..."

	for cmd in wget tar expect; do
		if [ -z "$(command -v "$cmd")" ]; then
			fail "Make sure these utilities are installed: wget tar expect"
		fi
	done

	if [ -d "$SRC_DIR" ] || [ -d "$OUT_DIR" ]; then
		fail "Some files left from the previous test, remove $SRC_DIR and $OUT_DIR"
	fi

	if [ ! -f "$SRC_TARBALL" ]; then
		wget "$KERNEL" -O "$SRC_TARBALL"
	fi

	CHECKSUM=$(sha256sum "$SRC_TARBALL" | awk '{print $1}')
	if [ "$CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
		fail "Unexpected sha256sum of the $SRC_TARBALL, remove $SRC_TARBALL and restart the test"
	fi

	mkdir -p "$SRC_DIR" "$OUT_DIR"
	tar -xf "$SRC_TARBALL" -C "$SRC_DIR" --strip-components=1

	for COMPILER in "${COMPILERS[@]}"; do
		python3 manage_images.py -d -b "$COMPILER"
		python3 manage_images.py -p -b "$COMPILER"
	done

	echo "[+] Everything is ready for the tests"
}

run_tests() {
	# Use $RUNTIME_FLAG without quotes since it may be empty (default value)

	echo -e $DELIMITER
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

	echo -e $DELIMITER
	echo "Testing some invalid arguments..."
	python3 -m coverage run -a --branch build_linux.py -p -d -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- O=invalid && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- CC=invalid && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- -j1 && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- ARCH=invalid && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- CROSS_COMPILE=invalid && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o /path/INVALID -- defconfig && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s /path/INVALID -o "$OUT_DIR" -- defconfig && exit 1
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -k /path/INVALID.conf && exit 1

	echo -e $DELIMITER
	echo "Testing quiet building..."
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -q -- defconfig

	echo -e $DELIMITER
	echo "Testing single-cpu building..."
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -t -- defconfig

	echo -e $DELIMITER
	echo "Testing building with the same directory..."
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -- defconfig
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$SRC_DIR" -- defconfig

	echo -e $DELIMITER
	echo "Testing building with external config..."
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$SRC_DIR" -- mrproper
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- defconfig
	cp "${OUT_DIR}/${ARCHS[0]}__${COMPILERS[0]}/.config" "./config"
	python3 -m coverage run -a --branch build_linux.py \
		$RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -k "./config" && exit 1
	python3 -m coverage run -a --branch build_linux.py \
		$RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -k "./config" -- defconfig
	python3 -m coverage run -a --branch build_linux.py \
		$RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -k "./config" -- defconfig
	echo "# CONFIG_EXAMPLE_FOOBAR is not set" >>"./config"
	python3 -m coverage run -a --branch build_linux.py \
		$RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -k "./config" -- defconfig && exit 1

	echo -e $DELIMITER
	echo "Testing interruption handling..."
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- mrproper
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- defconfig
	expect <<EOF
spawn python3 -m coverage run -a --branch build_linux.py -t $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR"
set timeout 2
expect {
	timeout {
		send "\x03"
		expect eof
	}
}
EOF
	expect <<EOF
spawn python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- menuconfig
set timeout 5
expect {
	timeout {
		send "\x03"
		send Y
		expect eof
	}
}
EOF
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$SRC_DIR" -- mrproper
	python3 -m coverage run -a --branch build_linux.py $RUNTIME_FLAG -a "${ARCHS[0]}" -c "${COMPILERS[0]}" -s "$SRC_DIR" -o "$OUT_DIR" -- mrproper
	if [ -e "./config" ]; then
		rm "./config"
	fi
}

cleanup() {
	if [ -e "$SRC_TARBALL" ] && [ -e "$SRC_DIR" ] && [ -e "$OUT_DIR" ]; then
		echo "It is safe to remove these directories: $SRC_TARBALL $SRC_DIR $OUT_DIR"
	fi
}

echo "Let's test build_linux.py..."
prepare_tests
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
