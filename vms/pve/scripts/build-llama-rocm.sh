# clean build
#
export HIP_PATH=$ROCM_PATH
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
  -DCMAKE_C_COMPILER=$ROCM_PATH/bin/amdclang \
  -DCMAKE_CXX_COMPILER=$ROCM_PATH/bin/amdclang++ \
  -DCMAKE_HIP_COMPILER=$ROCM_PATH/bin/amdclang++
echo "MAKE COMPLETE: ✅ "
echo "BUILD:"
cmake --build build-rocm --config Release -j$(nproc)
echo "✅ BUILD COMPLETE"