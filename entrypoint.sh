#!/bin/bash
set -euo pipefail

if [ -f /venv/main/bin/activate ]; then
  source /venv/main/bin/activate
fi

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== ComfyUI Provisioning Start ==="

APT_PACKAGES=()

PIP_PACKAGES=(
  "opencv-python-headless"
  "numba"
  "dynamicprompts"
  "piexif"
  "ultralytics"
  "dill"
)

NODES=(
  # --- из рабочего скрипта ---
  "https://github.com/kijai/ComfyUI-WanVideoWrapper"
  "https://github.com/chflame163/ComfyUI_LayerStyle"
  "https://github.com/kijai/ComfyUI-KJNodes"
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
  "https://github.com/kijai/ComfyUI-segment-anything-2"
  "https://github.com/cubiq/ComfyUI_essentials"
  "https://github.com/fq393/ComfyUI-ZMG-Nodes"
  "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
  "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
  "https://github.com/teskor-hub/NEW-UTILS.git"

  # --- общие (без дублей) ---
  "https://github.com/rgthree/rgthree-comfy.git"
  "https://github.com/yolain/ComfyUI-Easy-Use.git"

  # --- из твоего скрипта ---
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git"
  "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
  "https://github.com/WASasquatch/was-node-suite-comfyui.git"
  "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
  "https://github.com/adieyal/comfyui-dynamicprompts.git"

  # --- недостающие для этого workflow ---
  "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
  "https://github.com/alexopus/ComfyUI-Image-Saver.git"
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
  "https://github.com/Miosp/ComfyUI-FBCNN.git"
)

VAE_MODELS=(
  "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors"
)

UPSCALE_MODELS=(
  "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"
)

SAM_MODELS=(
  "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth"
)

IPADAPTER_MODELS=(
  "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin"
)

ULTRALYTICS_MODELS=(
  "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt"
  "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n.pt"
  "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt"
  "https://huggingface.co/Bingsu/adetailer/resolve/main/person_yolov8m-seg.pt"
  "https://huggingface.co/Tenofas/ComfyUI/resolve/main/ultralytics/bbox/Eyeful_v2-Paired.pt"
)

CHECKPOINT_MODELS=(
  "https://civitai.com/api/download/models/1643845"
  "https://civitai.com/api/download/models/2837020"
)

LORA_MODELS=(
  "https://civitai.com/api/download/models/1189052"
  "https://civitai.com/api/download/models/398847"
  "https://civitai.com/api/download/models/382152"
  "https://civitai.com/api/download/models/1835318"
  "https://civitai.com/api/download/models/2148484"
  "https://civitai.com/api/download/models/481798"
  "https://civitai.com/api/download/models/1387728"
  "https://civitai.com/api/download/models/2172230"
  "https://civitai.com/api/download/models/2300536"
  "https://civitai.com/api/download/models/1272693"
  "https://civitai.com/api/download/models/1253021"
  "https://civitai.com/api/download/models/1359711"
  "https://civitai.com/api/download/models/1755959"
  "https://civitai.com/api/download/models/556208"
)

provisioning_get_apt_packages() {
  if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
    echo "Устанавливаем apt packages..."
    apt-get update
    apt-get install -y "${APT_PACKAGES[@]}"
  fi
}

provisioning_clone_comfyui() {
  if [[ ! -d "${COMFYUI_DIR}" ]]; then
    echo "Клонируем ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
  fi
  cd "${COMFYUI_DIR}"
}

provisioning_install_base_reqs() {
  if [[ -f "${COMFYUI_DIR}/requirements.txt" ]]; then
    echo "Устанавливаем base requirements..."
    pip install --no-cache-dir -r "${COMFYUI_DIR}/requirements.txt"
  fi
}

provisioning_get_pip_packages() {
  if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
    echo "Устанавливаем pip packages..."
    pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    pip install --no-cache-dir git+https://github.com/facebookresearch/segment-anything.git
  fi
}

provisioning_get_nodes() {
  mkdir -p "${COMFYUI_DIR}/custom_nodes"
  cd "${COMFYUI_DIR}/custom_nodes"

  for repo in "${NODES[@]}"; do
    dir="${repo##*/}"
    dir="${dir%.git}"
    path="./${dir}"

    if [[ -d "${path}" ]]; then
      echo "Обновляем ноду: ${dir}"
      (
        cd "${path}"
        git pull --ff-only 2>/dev/null || {
          git fetch --all
          git reset --hard origin/main || true
        }
      )
    else
      echo "Клонируем ноду: ${dir}"
      git clone --recursive "${repo}" "${path}" || echo "[!] Clone failed: ${repo}"
    fi

    if [[ -f "${path}/requirements.txt" ]]; then
      echo "Зависимости для ${dir}..."
      pip install --no-cache-dir -r "${path}/requirements.txt" || echo "[!] pip requirements failed for ${dir}"
    fi

    if [[ -f "${path}/install.py" ]]; then
      echo "Install script для ${dir}..."
      python "${path}/install.py" || echo "[!] install.py failed for ${dir}"
    fi
  done
}

provisioning_get_files() {
  if [[ $# -lt 2 ]]; then
    return
  fi

  local dir="$1"
  shift
  local files=("$@")

  mkdir -p "${dir}"
  echo "Скачивание ${#files[@]} файл(ов) → ${dir}..."

  for url in "${files[@]}"; do
    echo "→ ${url}"

    if [[ "${url}" =~ civitai\.com && -n "${CIVITAI_TOKEN:-}" ]]; then
      wget -nc --content-disposition --show-progress \
        -e dotbytes=4M -P "${dir}" \
        "${url}?token=${CIVITAI_TOKEN}" || echo "[!] Download failed: ${url}"

    elif [[ "${url}" =~ huggingface\.co && -n "${HF_TOKEN:-}" ]]; then
      wget -nc --content-disposition --show-progress \
        -e dotbytes=4M -P "${dir}" \
        --header="Authorization: Bearer ${HF_TOKEN}" \
        "${url}" || echo "[!] Download failed: ${url}"

    else
      wget -nc --content-disposition --show-progress \
        -e dotbytes=4M -P "${dir}" \
        "${url}" || echo "[!] Download failed: ${url}"
    fi

    echo ""
  done
}

provisioning_start() {
  echo ""
  echo "##############################################"
  echo "# ComfyUI X-MODE SETUP #"
  echo "##############################################"
  echo ""

  provisioning_get_apt_packages
  provisioning_clone_comfyui
  provisioning_install_base_reqs
  provisioning_get_nodes
  provisioning_get_pip_packages

  provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/sams" "${SAM_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/ipadapter" "${IPADAPTER_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox" "${ULTRALYTICS_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
  provisioning_get_files "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"

  if [[ -f "${COMFYUI_DIR}/custom_nodes/ComfyUI-Impact-Pack/install.py" ]]; then
    echo "Running Impact Pack installer..."
    python "${COMFYUI_DIR}/custom_nodes/ComfyUI-Impact-Pack/install.py" || echo "[!] Impact Pack install.py failed"
  fi

  echo ""
  echo "Provisioning complete → Starting ComfyUI..."
  echo ""
}

if [[ ! -f /.noprovisioning ]]; then
  provisioning_start
fi

echo "=== Запуск ComfyUI ==="
cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
