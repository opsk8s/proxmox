#!/bin/bash
cd
pwd
rm -fR .vllm/
uv venv .vllm --python 3.14 --seed

echo 'export PYTHONPATH=$VIRTUAL_ENV/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi' >> ~/.vllm/bin/activate
echo 'export FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE' >> ~/.vllm/bin/activate
echo 'export AITER_USE_SYSTEM_TRITON=1' >> ~/.vllm/bin/activate
echo 'export PYTORCH_ROCM_ARCH="gfx1201"' >> ~/.vllm/bin/activate

source .vllm/bin/activate
# export PYTHONPATH=$VIRTUAL_ENV/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi
# export FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE
# export AITER_USE_SYSTEM_TRITON=1

uv pip install ninja cmake wheel pybind11 flydsl
uv pip install --index-url https://repo.amd.com/rocm/whl-multi-arch/ "torch[device-gfx1201]==2.11.0+rocm7.14.0" "torchvision[device-gfx1201]==0.26.0+rocm7.14.0" "torchaudio==2.11.0+rocm7.14.0"

uv pip install https://rocm.frameworks.amd.com/whl-multi-arch/vllm-rdna/flash-attn/flash_attn-2.8.3-py3-none-any.whl

uv pip install https://rocm.frameworks.amd.com/whl-multi-arch/vllm-rdna/vllm/vllm-0.23.1.dev1%2Brocm7.14.0.g9ddef7117.d20260715-cp314-cp314-linux_x86_64.whl


uv pip uninstall flash-attn aiter

rm -fR builds
mkdir builds 

cd builds
git clone -b v2.8.3.post1 --recursive https://github.com/Dao-AILab/flash-attention
cd flash-attention
BUILD_TARGET=rocm python setup.py install

cd
cd builds
git clone --recursive https://github.com/ROCm/aiter.git
cd aiter
python setup.py develop

cd 
cp -r /opt/rocm/share/amd_smi ~/builds/amd_smi
chown -R llm:llm builds/
uv pip install builds/amd_smi/

# uv pip install --upgrade numba scipy huggingface-hub[cli]  setuptools_scm

#cd
#cd builds
#git clone --recursive https://github.com/vllm-project/vllm
#cd vllm	
#uv pip install -r requirements/rocm.txt
#python setup.py develop

#uv pip install https://rocm.frameworks.amd.com/whl-multi-arch/vllm-rdna/vllm/vllm-0.23.1.dev1%2Brocm7.14.0.g9ddef7117.d20260715-cp314-cp314-linux_x86_64.whl

