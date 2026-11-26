# build vllm
source $HOME/.bashrc
rm -fR $HOME/.vllm
uv venv $HOME/.vllm --python 3.14 --seed
source $HOME/.vllm/bin/activate

uv pip install ninja cmake wheel pybind11
uv pip install --index-url https://download.pytorch.org/whl/cu130 \
       "torch==2.12.0+cu130" \
       "torchvision==0.27.0+cu130" \
       "torchaudio==2.11.0+cu130"

uv pip install "flash-attn==2.8.3"
uv pip install "vllm==0.27.0"

python -m pip install --upgrade "tensorizer==2.12.1"
