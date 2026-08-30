# clean build
#
echo "START:"
cd $HOME/llama.cpp
pwd
echo "CLEANUP: rm -fr build"
rm -rf build-vulkan
echo "CLEANUP COMPLETE: ✅ "
echo "PULL:"
git pull
echo "PULL COMPLETE: ✅ "
echo "MAKE: gfx1201"
cmake -B build-vulkan -DGGML_CCACHE=ON -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release -DAMDGPU_TARGETS=gfx1201
echo "MAKE COMPLETE: ✅ "
echo "BUILD:"
cmake --build build-vulkan --config Release -j$(nproc)
echo "✅ BUILD COMPLETE"