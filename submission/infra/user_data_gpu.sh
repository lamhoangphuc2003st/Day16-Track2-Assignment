#!/bin/bash
set -e

# Install Docker
apt-get update -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# Install NVIDIA drivers and container toolkit
apt-get install -y linux-headers-$(uname -r)
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Run vLLM with the Gemma model
docker run -d \
  --gpus all \
  --restart unless-stopped \
  -p 8000:8000 \
  -e HUGGING_FACE_HUB_TOKEN="${hf_token}" \
  vllm/vllm-openai:latest \
  --model "${model_id}" \
  --dtype half \
  --max-model-len 4096
