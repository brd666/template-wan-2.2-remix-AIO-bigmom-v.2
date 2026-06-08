#!/bin/bash

COMFY_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$CUSTOM_NODES_DIR"
MODELS_DIR="$COMFY_DIR/models"
VENV_PYTHON="/venv/main/bin/python"
CIVITAI_TOKEN="93edfd8cf30d4caf7cdb82d6a92c475b"

download_file() {
    local url=$1
    local dir=$2
    local filename=$3
    echo "Скачивание $filename в $dir..."
    mkdir -p "$dir"
    wget -c -O "$dir/$filename" "$url"
}

download_civitai() {
    local url=$1
    local dir=$2
    local filename=$3
    echo "Скачивание $filename с Civitai в $dir..."
    mkdir -p "$dir"
    curl -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" "$url" -o "$dir/$filename"
}

echo "=== 1. Установка кастомных нод ==="
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR" || exit

git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git
git clone https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git
git clone https://github.com/rgthree/rgthree-comfy.git
git clone https://github.com/yolain/ComfyUI-Easy-Use.git
git clone https://github.com/WASasquatch/was-node-suite-comfyui.git
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
git clone https://github.com/adieyal/comfyui-dynamicprompts.git
git clone https://github.com/kijai/comfyui-kjnodes.git
git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git
git clone https://github.com/Miosp/ComfyUI-FBCNN.git
git clone https://github.com/alexopus/ComfyUI-Image-Saver.git
git clone https://github.com/zmwv823/comfyui-gemini.git
git clone https://github.com/RockOfRock/ComfyUI_Comfyroll_CustomNodes.git
git clone https://github.com/bash-bunni/mikey_nodes.git
git clone https://github.com/KohakuBlueleaf/z-tipo-extension.git
git clone https://github.com/melMass/comfyui-lora-manager.git
git clone https://github.com/gogod666/ComfyUI-PPM.git

echo "=== 2. Установка Python-зависимостей ==="
cd "$COMFY_DIR" || exit

$VENV_PYTHON -m pip install opencv-python-headless numba dynamicprompts piexif ultralytics dill scipy imageio insightface google-generativeai
$VENV_PYTHON -m pip install git+https://github.com/facebookresearch/segment-anything.git

if [ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py" ]; then
    $VENV_PYTHON "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py"
fi

$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/was-node-suite-comfyui/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/ComfyUI-Easy-Use/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/comfyui-dynamicprompts/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/comfyui-kjnodes/requirements.txt"

echo "=== 3. Загрузка базовых моделей ==="
download_file "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" "$MODELS_DIR/upscale_models" "4x_foolhardy_Remacri.pth"
download_file "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" "$MODELS_DIR/sams" "sam_vit_b_01ec64.pth"

echo "=== 4. Загрузка моделей IP-Adapter и CLIP Vision ==="
download_file "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$MODELS_DIR/ipadapter" "ip-adapter-faceid-plusv2_sdxl.bin"
download_file "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$MODELS_DIR/clip_vision" "CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors"

# Системные файлы для работы InsightFace (либы FaceID)
mkdir -p /root/.insightface/models
download_file "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip" "/root/.insightface/models" "buffalo_l.zip"

echo "=== 5. Загрузка моделей ControlNet ==="
download_file "https://huggingface.co/StabilityAI/control-lora/resolve/main/control-LoRA-canny/control-lora-canny-rank256.safetensors" "$MODELS_DIR/controlnet" "control-lora-canny-rank256.safetensors"
download_file "https://huggingface.co/gandor/noobaiXLControlnet_openpose/resolve/main/noobaiXLControlnet_openposeModel.safetensors" "$MODELS_DIR/controlnet" "noobaiXLControlnet_openposeModel.safetensors"

echo "=== 6. Загрузка моделей Ultralytics (ADetailer) ==="
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt" "$MODELS_DIR/ultralytics/bbox" "face_yolov9c.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov8s.pt" "$MODELS_DIR/ultralytics/bbox" "hand_yolov8s.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt" "$MODELS_DIR/ultralytics/bbox" "hand_yolov9c.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/Eyeful_v2-Paired.pt" "$MODELS_DIR/ultralytics/bbox" "Eyeful_v2-Paired.pt"
download_file "https://huggingface.co/dustysand/yolov8_segmentation/resolve/main/ntd11_anime_nsfw_segm_v5-variant1.pt" "$MODELS_DIR/ultralytics/segm" "ntd11_anime_nsfw_segm_v5-variant1.pt"
download_file "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11m-seg.pt" "$MODELS_DIR/ultralytics/segm" "yolo11m-seg.pt"

echo "=== 7. Загрузка текстовых моделей (TIPO) ==="
download_file "https://huggingface.co/KBlueLeaf/TIPO-200M/resolve/main/TIPO-200M-ft2-F16.gguf" "$MODELS_DIR/tipo" "TIPO-200M-ft2-F16.gguf"

echo "=== 8. Загрузка Checkpoint ==="
mkdir -p "$MODELS_DIR/checkpoints/Illustrious/anime"
download_civitai "https://civitai.com/api/download/models/1643845" "$MODELS_DIR/checkpoints/Illustrious/anime" "illustriousRealismByKlaabu.safetensors"

echo "=== 9. Загрузка LoRA ==="
download_civitai "https://civitai.com/api/download/models/1189052" "$MODELS_DIR/loras" "incase_style_v3-1_ponyxl_ilff.safetensors"
download_civitai "https://civitai.com/api/download/models/145837" "$MODELS_DIR/loras" "g0th1cPXL.safetensors"
download_civitai "https://civitai.com/api/download/models/382152" "$MODELS_DIR/loras" "Expressive_H-000001.safetensors"
download_civitai "https://civitai.com/api/download/models/1835318" "$MODELS_DIR/loras" "Breast Size Slider - Illustrious - V2_alpha1.0_rank4_noxattn_last.safetensors"
download_civitai "https://civitai.com/api/download/models/2148484" "$MODELS_DIR/loras" "Femenine_body_hq_illu.safetensors"
download_civitai "https://civitai.com/api/download/models/481798" "$MODELS_DIR/loras" "Sinozick_Style_XL_Pony.safetensors"
download_civitai "https://civitai.com/api/download/models/1387728" "$MODELS_DIR/loras" "Jolly_Jacks_biggest_beasts_Illustrious.safetensors"
download_civitai "https://civitai.com/api/download/models/2172230" "$MODELS_DIR/loras" "devmgf_Style.safetensors"
download_civitai "https://civitai.com/api/download/models/2300536" "$MODELS_DIR/loras" "Hyper_Muscles_V4.2.safetensors"
download_civitai "https://civitai.com/api/download/models/1272693" "$MODELS_DIR/loras" "Spray Tan Slider_Pony.safetensors"
download_civitai "https://civitai.com/api/download/models/1253021" "$MODELS_DIR/loras" "Pony Realism Slider.safetensors"
download_civitai "https://civitai.com/api/download/models/1359711" "$MODELS_DIR/loras" "AmateurStyle_v3_PONY_REALISM.safetensors"
download_civitai "https://civitai.com/api/download/models/1755959" "$MODELS_DIR/loras" "amateur_photo_v2.safetensors"
download_civitai "https://civitai.com/api/download/models/556208" "$MODELS_DIR/loras" "igbaddie-PN.safetensors"

# Скрытые LoRA, прописанные жестко в пайплайнах инпейнтинга (ADetailer Edit Pipes)
mkdir -p "$MODELS_DIR/loras/Illustrious/concept"
download_civitai "https://civitai.com/api/download/models/255551" "$MODELS_DIR/loras/Illustrious/concept" "Eyes_for_Illustrious_Lora_Perfect_anime_eyes.safetensors"
download_civitai "https://civitai.com/api/download/models/782627" "$MODELS_DIR/loras" "detailed_hand_focus_style_illustriousXL_v1.1.safetensors"

echo "=== Настройка завершена! Пайплайн готов к работе. ==="
