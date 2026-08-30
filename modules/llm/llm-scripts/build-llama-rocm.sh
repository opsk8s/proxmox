# clean build
#
echo "START:"
cd $HOME/llama.cpp
pwd 
echo "CLEANUP: rm -fr build"
rm -rf build-rocm
echo "CLEANUP COMPLETE: ✅ "
echo "PULL:"
git pull
echo "PULL COMPLETE: ✅ "
echo "MAKE: gfx1201"
cmake -B build-rocm \
  -DGGML_HIP=ON \
  -DCMAKE_HIP_ARCHITECTURES="gfx1201" \
  -DAMDGPU_TARGETS="gfx1201" \
  -DGGML_HIP_MMQ_MFMA=ON \
  -DGGML_HIP_NO_VMM=ON
echo "MAKE COMPLETE: ✅ "
echo "BUILD:"
cmake --build build-rocm --config Release -j$(nproc)
echo "✅ BUILD COMPLETE"