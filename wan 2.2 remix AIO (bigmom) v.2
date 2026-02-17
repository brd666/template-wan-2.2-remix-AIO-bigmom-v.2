#!/bin/bash

# ==========================================
# KIRILL'S WAN 2.2 REMIX SETUP SCRIPT
# Optimized for Vast.ai / RunPod
# ==========================================

# 1. Определение путей (Стандарт для Vast.ai)
COMFY_DIR="/workspace/ComfyUI"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

echo "🚀 Начинаем установку окружения для Wan 2.2 Remix..."

# 2. Установка системных зависимостей (если нужно для видео)
apt-get update && apt-get install -y ffmpeg aria2

# 3. Установка Custom Nodes
# Мы клонируем только то, что есть в твоем JSON

cd $NODES_DIR

# --- WanVideoWrapper (Главная нода) ---
if [ ! -d "ComfyUI-WanVideoWrapper" ]; then
    echo "📦 Установка WanVideoWrapper..."
    git clone https://github.com/Kijai/ComfyUI-WanVideoWrapper.git
    cd ComfyUI-WanVideoWrapper
    pip install -r requirements.txt
    cd ..
fi

# --- VideoHelperSuite (VHS) ---
if [ ! -d "ComfyUI-VideoHelperSuite" ]; then
    echo "📦 Установка VideoHelperSuite..."
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
    cd ComfyUI-VideoHelperSuite
    pip install -r requirements.txt
    cd ..
fi

# --- KJNodes ---
if [ ! -d "ComfyUI-KJNodes" ]; then
    echo "📦 Установка KJNodes..."
    git clone https://github.com/kijai/ComfyUI-KJNodes.git
    cd ComfyUI-KJNodes
    pip install -r requirements.txt
    cd ..
fi

# --- Inspire Pack ---
if [ ! -d "ComfyUI-Inspire-Pack" ]; then
    echo "📦 Установка Inspire Pack..."
    git clone https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git
    cd ComfyUI-Inspire-Pack
    pip install -r requirements.txt
    cd ..
fi

# --- Easy Use ---
if [ ! -d "ComfyUI-Easy-Use" ]; then
    echo "📦 Установка Easy Use..."
    git clone https://github.com/yolain/ComfyUI-Easy-Use.git
    cd ComfyUI-Easy-Use
    pip install -r requirements.txt
    cd ..
fi

# --- Custom Scripts (pysssss) ---
if [ ! -d "ComfyUI-Custom-Scripts" ]; then
    echo "📦 Установка Custom Scripts..."
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git
fi

# --- Dynamic Prompts ---
if [ ! -d "comfyui-dynamicprompts" ]; then
    echo "📦 Установка Dynamic Prompts..."
    git clone https://github.com/adieyal/comfyui-dynamicprompts.git
    cd comfyui-dynamicprompts
    pip install -r requirements.txt
    cd ..
fi

# --- Frame Interpolation (RIFE) ---
if [ ! -d "ComfyUI-Frame-Interpolation" ]; then
    echo "📦 Установка Frame Interpolation..."
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
    cd ComfyUI-Frame-Interpolation
    pip install -r requirements.txt
    cd ..
fi

# 4. Загрузка Моделей
# Используем ссылки из твоего воркфлоу (Node 159)

echo "⬇️ Загрузка моделей..."

# --- Diffusion Models (Wan 2.2 Remix) ---
# Путь может быть models/diffusion_models или models/unet в зависимости от конфигурации
# WanWrapper обычно ищет в diffusion_models
cd $MODELS_DIR/diffusion_models
      
echo "Downloading Wan2.2 High Lighting..."
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" -o "Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors"

echo "Downloading Wan2.2 Low Lighting..."
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" -o "Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors"

# --- Text Encoders (T5) ---
cd $MODELS_DIR/text_encoders
echo "Downloading T5 Encoder..."
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/dci05049/wan-video/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors" -o "nsfw_wan_umt5-xxl_fp8_scaled.safetensors"

# --- VAE ---
cd $MODELS_DIR/vae
echo "Downloading Wan VAE..."
aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" -o "wan_2.1_vae.safetensors"

# --- LoRAs ---
# ВАЖНО: В твоем JSON не было ссылок на эти файлы, только названия.
# Тебе нужно вставить сюда прямые ссылки (например, с Civitai или HuggingFace), если они не лежат локально.
cd $MODELS_DIR/loras
echo "⚠️ Downloading LoRAs (Placeholder URLs - EDIT THIS SECTION)..."

# Пример (Замени URL на реальные!):
# aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "LINK_TO_NSFW-22-L-e8.safetensors" -o "NSFW-22-L-e8.safetensors"
# aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "LINK_TO_NSFW-22-H-e8.safetensors" -o "NSFW-22-H-e8.safetensors"


# --- RIFE (Frame Interpolation) ---
# Обычно скачивается автоматически при первом запуске, но можно создать папку
mkdir -p $NODES_DIR/ComfyUI-Frame-Interpolation/ckpts/rife

echo "✅ Установка завершена! Перезапусти ComfyUI."
