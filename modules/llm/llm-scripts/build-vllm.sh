# build vllm
source $HOME/.bashrc
rm -fR $HOME/.vllm
uv venv $HOME/.vllm --python 3.14 --seed

echo 'export PYTHONPATH=$VIRTUAL_ENV/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi' >> $HOME/.vllm/bin/activate
echo 'export FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE' >> $HOME/.vllm/bin/activate
source $HOME/.vllm/bin/activate

uv pip install ninja cmake wheel pybind11 flydsl
uv pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ "rocm[libraries,device-gfx1201]==10.0.0"
uv pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
       "torch[device-gfx1201]==2.12.0+rocm10.0.0" \
       "torchvision[device-gfx1201]==0.27.0+rocm10.0.0" \
       "torchaudio==2.11.0+rocm10.0.0"

uv pip install https://rocm.frameworks.amd.com/whl-multi-arch/vllm/flash-attn/flash_attn-2.8.3-cp314-cp314-linux_x86_64.whl
uv pip install https://rocm.frameworks.amd.com/whl-multi-arch/vllm/amd-aiter/amd_aiter-0.1.20.post1-cp314-cp314-linux_x86_64.whl
uv pip install https://rocm.frameworks.amd.com/whl-multi-arch/vllm/vllm/vllm-0.27.1.dev5%2Brocm10.0.0.gf46a9dfe2.d20260826-cp314-cp314-linux_x86_64.whl

python -m pip install --upgrade "tensorizer==2.12.1"