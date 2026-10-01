# Darling - macOS runtime environment for Linux
# https://github.com/darlinghq/darling
#
# This image contains a pre-built Darling installation.
#
# IMPORTANT: Darling requires the darling-mach kernel module loaded on the host.
# Without it, `darling shell` will fail with "Failed to open /dev/mach" =[.
#
# Usage:
#   docker run --rm --privileged \
#     darlinghq/darling darling shell echo "Hello from macOS runtime"

FROM ubuntu:22.04
LABEL maintainer="Darling Project <https://darlinghq.org>" \
      name="darlinghq/darling" \
      description="Darling - macOS runtime environment for Linux" \
      url="https://github.com/darlinghq/darling"

# Install build dependencies. The list tracks debian/control's Build-Depends,
# which is the authoritative statement of what this superproject needs to build;
# ci/Debian.Dockerfile is the same list as an image.
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    clang \
    bison \
    flex \
    libfuse-dev \
    libudev-dev \
    pkg-config \
    libc6-dev-i386 \
    linux-headers-generic \
    gcc-multilib \
    libcairo2-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libtiff5-dev \
    libfreetype6-dev \
    git \
    git-lfs \
    libelf-dev \
    libxml2-dev \
    libegl1-mesa-dev \
    libfontconfig1-dev \
    libbsd-dev \
    libxrandr-dev \
    libxcursor-dev \
    libgif-dev \
    libavutil-dev \
    libpulse-dev \
    libavformat-dev \
    libavcodec-dev \
    libswresample-dev \
    libdbus-1-dev \
    libxkbfile-dev \
    libssl-dev \
    llvm-dev \
    libvulkan-dev \
    ninja-build \
    libc++-dev \
    libc++abi-dev \
    libcap2-bin \
    libcap-dev \
    python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /src/darling
COPY . .

# Initialize submodules from the already-copied .git data (no network fetch needed)
RUN git submodule update --init --recursive --no-fetch 2>/dev/null || \
    git submodule update --init --recursive

# src/external/swift ships its overlay dylibs and frameworks through git-lfs
# (darling-swift's .gitattributes marks *.dylib and the Combine/CryptoKit/... trees
# `filter=lfs`), and its CMakeLists.txt installs whatever `file(GLOB "*.dylib")`
# finds. Without a pull those are 130-byte pointer files that still match the glob,
# so the build succeeds and the installed /usr/lib/swift is text. Same step as
# ci/Jenkinsfile:46.
RUN git -C src/external/swift lfs install --local && \
    git -C src/external/swift lfs pull

# Build and install
#
# Key cmake flags:
# - CMAKE_C_FLAGS_INIT / CMAKE_CXX_FLAGS_INIT: appended to CMake's internal flags.
#   CMAKE_C_FLAGS would replace them, and CMakeLists.txt:136-137 appends the
#   IGNORED_WARNINGS set (which carries -Wno-nullability-completeness,
#   -Wno-deprecated-declarations and -Wno-availability) on top of whatever it is
#   given, so the suppression survives either way. Kept as *_INIT because the
#   vendored Apple dylib cross-compilation needs those warnings off and the
#   ignoring must not depend on flag ordering.
# - TARGET_i386=OFF: skip the 32-bit slices. The Debian package builds them
#   (CMakeLists.txt:162), so this image is x86_64-only; the ranlib "no symbols"
#   noise and the i386 linker failures they drag in are not worth a guest
#   capability the runtime image cannot use on an arm64 host anyway.
RUN mkdir -p build && cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_FLAGS_INIT="-Wno-incompatible-pointer-types" \
        -DCMAKE_CXX_FLAGS_INIT="-Wno-incompatible-pointer-types" \
        -DTARGET_i386=OFF \
        -GNinja && \
    ninja -j$(nproc) && \
    ninja install && \
    cd / && rm -rf /src/darling/build

WORKDIR /root

CMD ["darling", "shell"]
