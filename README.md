# rocknix-turnip

glibc-ARM64 Mesa Turnip (Vulkan) drivers for the ROCKNIX **GPU Driver Manager** (Odin 3 / SM8750, Adreno 830).

The on-device `/usr/bin/gpu-driver` fetches `manifest.json` from the **latest** release and can install any listed driver per-game. Built from the ROCKNIX toolchain (matching ABI) by `packages/tools/gpu-driver/ci/build-turnip-catalog.sh`.
