#!/usr/bin/env bash
# clean build
set -euo pipefail
# non-interactive shells don't have the CUDA toolkit on PATH
export PATH="/usr/local/cuda/bin:$PATH"
export CUDACXX=/usr/local/cuda/bin/nvcc
echo "START:"
cd "$HOME/llama.cpp"
pwd
echo "CLEANUP: rm -fr build-cuda"
rm -rf build-cuda
echo "CLEANUP COMPLETE"
echo "PULL:"
git pull
echo "PULL COMPLETE"
echo "MAKE: sm_86 (RTX 3090)"
cmake -B build-cuda \
  -DGGML_CCACHE=ON \
  -DGGML_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES="86"
echo "MAKE COMPLETE"
echo "BUILD:"
cmake --build build-cuda --config Release -j"$(nproc)"
echo "BUILD COMPLETE"
