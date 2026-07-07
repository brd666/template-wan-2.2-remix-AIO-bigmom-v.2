#!/bin/bash

# ==========================================
# UNIVERSAL WAN 2.2 INSTALLER (Vast.ai / Ubuntu 22/24)
# Template: anima princess
# ==========================================

# 1. НАСТРОЙКА ПЕРЕМЕННЫХ И ПУТЕЙ
if [ -f "/venv/main/bin/python" ]; then
    PY_EXEC="/venv/main/bin/python"
    PIP_EXEC="/venv/main/bin/pip"
    echo "✅ Найден venv python: $PY_EXEC"
else
    PY_EXEC="python3"
    PIP_EXEC="pip3"
    # Для Python 3.11+ (Ubuntu 24.04) нужен флаг прорыва системных пакетов
    if python3 -c "import sys; print(sys.version_info >= (3, 11))" | grep -q "True"; then
        EXTRA_PIP_FLAGS="--break-system-packages"
    fi
    echo "⚠️ Используем системный python3 $EXTRA_PIP_FLAGS"
fi

COMFY_DIR="/workspace/ComfyUI"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

# 2. УСТАНОВКА СИСТЕМНЫХ УТИЛИТ (С защитой от сбоев сети)
echo "⚙️ Установка системных утилит..."
export DEBIAN_FRONTEND=noninteractive

# Пытаемся обновить репозитории 3 раза (на случай лагов security.ubuntu.com)
for i in {1..3}; do 
    apt-get update --fix-missing && break || (echo "Retry apt-get update..." && sleep 5)
done

apt-get install -y aria2 ffmpeg libgl1 libglx-mesa0 wget git

# 3. ПОДГОТОВКА БИБЛИОТЕК PYTHON
echo "💊 Обновление базовых библиотек..."
$PIP_EXEC install --upgrade pip $EXTRA_PIP_FLAGS
$PIP_EXEC install $EXTRA_PIP_FLAGS opencv-python-headless accelerate dynamicprompts imageio-ffmpeg onnxruntime

# 4. УСТАНОВКА CUSTOM NODES
mkdir -p "$NODES_DIR"
cd "$NODES_DIR"

install_node() {
    REPO_URL=$1
    DIR_NAME=$2
    if [ ! -d "$DIR_NAME" ]; then
        echo "⬇️ Клонирование $DIR_NAME..."
        git clone --depth 1 $REPO_URL
    else
        echo "🔄 $DIR_NAME найден, обновляю..."
        cd "$DIR_NAME" && git pull && cd ..
    fi
    
    if [ -f "$DIR_NAME/requirements.txt" ]; then
        echo "   📦 Ставлю зависимости для $DIR_NAME..."
        $PIP_EXEC install $EXTRA_PIP_FLAGS -r "$DIR_NAME/requirements.txt"
    fi
}

install_node 'https://github.com/willmiao/ComfyUI-Lora-Manager' 'ComfyUI-Lora-Manager'
install_node 'https://github.com/ltdrdata/ComfyUI-Manager' 'ComfyUI-Manager'
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Pack' 'ComfyUI-Impact-Pack'
install_node 'https://github.com/yolain/ComfyUI-Easy-Use' 'ComfyUI-Easy-Use'
install_node 'https://github.com/aining2022/ComfyUI_Swwan' 'ComfyUI_Swwan'
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Subpack' 'ComfyUI-Impact-Subpack'
install_node 'https://github.com/DemonGatanjieu/Anomalous_Model_Browser' 'Anomalous_Model_Browser'
install_node 'https://github.com/Aryan185/ComfyUI-VertexAPI' 'ComfyUI-VertexAPI'
install_node 'https://github.com/rgthree/rgthree-comfy' 'rgthree-comfy'
install_node 'https://github.com/pamparamm/ComfyUI-ppm' 'ComfyUI-ppm'
install_node 'https://github.com/ltdrdata/was-node-suite-comfyui' 'was-node-suite-comfyui'
install_node 'https://github.com/WASasquatch/was-node-suite-comfyui' 'was-node-suite-comfyui'

# 5. СКАЧИВАНИЕ МОДЕЛЕЙ (С поддержкой wget в случае провала aria2)
echo "⬇️ Скачивание моделей (Wan 2.2)..."

download_model() {
    local URL="$1"
    local FILENAME=$(echo "$2" | tr '\\' '/')
    local TARGET_DIR="$3"
    
    mkdir -p "$TARGET_DIR"
    local DIR_PART=$(dirname "$FILENAME")
    if [ "$DIR_PART" != "." ]; then
        mkdir -p "$TARGET_DIR/$DIR_PART"
    fi
    
    if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
        echo "   🚀 Загрузка $FILENAME..."
        
        # Попытка №1: aria2 (многопоточность)
        if command -v aria2c &> /dev/null; then
            if [[ "$URL" =~ "civitai.com" && -n "$CIVITAI_TOKEN" ]]; then
                aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M --header="Authorization: Bearer $CIVITAI_TOKEN" "$URL" -d "$TARGET_DIR" -o "$FILENAME"
            elif [[ "$URL" =~ "huggingface.co" && -n "$HF_TOKEN" ]]; then
                aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M --header="Authorization: Bearer $HF_TOKEN" "$URL" -d "$TARGET_DIR" -o "$FILENAME"
            else
                aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M "$URL" -d "$TARGET_DIR" -o "$FILENAME"
            fi
        fi
        
        # Попытка №2: wget (если aria2 не скачал или его нет)
        if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
            echo "   ⚠️ aria2 не справился, использую wget..."
            if [[ "$URL" =~ "civitai.com" && -n "$CIVITAI_TOKEN" ]]; then
                wget --header="Authorization: Bearer $CIVITAI_TOKEN" -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
            elif [[ "$URL" =~ "huggingface.co" && -n "$HF_TOKEN" ]]; then
                wget --header="Authorization: Bearer $HF_TOKEN" -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
            else
                wget -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
            fi
        fi
    else
        echo "   ✅ $FILENAME уже существует и не пустой."
    fi
}

# Set CIVITAI_TOKEN from environment if present
TOKEN="${CIVITAI_TOKEN}"

download_model 'https://huggingface.co/adbrasi/wanlotest/resolve/main/Eyeful_v2-Individual.pt' 'Eyeful_v2-Individual.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt' 'face_yolov9c.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/Nudimmud/adetailers/resolve/main/ntd11_anime_nsfw_segm_v5-variant1.pt' 'ntd11_anime_nsfw_segm_v5-variant1.pt' "$MODELS_DIR/ultralytics/segm"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt' 'hand_yolov9c.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth' '4x_foolhardy_Remacri.pth' "$MODELS_DIR/upscale_models"
download_model 'https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth' 'sam_vit_b_01ec64.pth' "$MODELS_DIR/sams"
download_model 'https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors' 'qwen_image_vae.safetensors' "$MODELS_DIR/vae"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/person_yolov8m-seg.pt' 'person_yolov8m-seg.pt' "$MODELS_DIR/ultralytics/segm"
download_model 'https://huggingface.co/Kutches/Anim4/resolve/441297abd33597506309ca63615d8a25c7041834/qwen_3_06b_base.safetensors' 'qwen_3_06b_base.safetensors' "$MODELS_DIR/text_encoders"
download_model 'https://civitai.red/api/download/models/2988052?token='$TOKEN 'hyper_muscles_anima_v1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2979642?token='$TOKEN 'anima-turbo-lora-v0.2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3022620?token='$TOKEN 'GothicNeonAnima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3026718?token='$TOKEN 'background_detailer_v1anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2902360?token='$TOKEN 'hyper_breastsamina.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3031464?token='$TOKEN 'incase23_lora.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3035023?token='$TOKEN 'anima_futanari_v3.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2985705?token='$TOKEN 'Flar_ANIMA_BASE.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2817661?token='$TOKEN 'dark_art_style_Anima-step00002750.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2972344?token='$TOKEN 'csr-AnimaB_V10-V2-CAME.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3007041?token='$TOKEN 'purple_tarot.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3021317?token='$TOKEN 'AshleyGraves_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2987991?token='$TOKEN 'VioletParr_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2992612?token='$TOKEN 'kei_student_blue_archive_anima-base-v1_0_lokr_f8-000012_fp32.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2980649?token='$TOKEN 'android-18-anime-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3089781?token='$TOKEN 'Elsa_AnimaBaseV10_byKonan_edited.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2987962?token='$TOKEN 'KallenKouzuki_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2960406?token='$TOKEN 'Eida_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/52804?token='$TOKEN 'Azula.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3069592?token='$TOKEN 'April_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2862867?token='$TOKEN 'NagatoroHayase_Anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3059477?token='$TOKEN 'Invisigal_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2812143?token='$TOKEN 'MatoiRyuuko_AnimaPreview2_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2950793?token='$TOKEN 'Cynthia_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3062723?token='$TOKEN 'Lifeguard-000080.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3057534?token='$TOKEN 'danmomo_ANIMA_V1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3016639?token='$TOKEN 'nier2b_anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2974514?token='$TOKEN 'yoruichi-shihouin-anime-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2983402?token='$TOKEN 'fern-s1-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3089831?token='$TOKEN 'Moana_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3072323?token='$TOKEN 'Azula_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2974473?token='$TOKEN 'KushinaUzumaki_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2785765?token='$TOKEN 'Mavis_AnimaPreview2_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3086321?token='$TOKEN 'novaAnimeAM_v30.safetensors' "$MODELS_DIR/diffusion_models"
download_model 'https://civitai.com/api/download/models/2871368?token='$TOKEN 'HiiragiUtena_AnimaPreview3_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3092150?token='$TOKEN 'Sally_Acorn-Sonic_Archie_Comics-Illustrious.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3017546?token='$TOKEN 'sasami_tsunami_anima_v700.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2987417?token='$TOKEN 'rukia-kuchiki-anime-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2987404?token='$TOKEN 'roxy-migurdia-s1-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2886012?token='$TOKEN 'Reze_t1-000006.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2968063?token='$TOKEN 'RavenTT_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2988303?token='$TOKEN 'PrincessJasmineAladdin v2_BaseAnima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2984571?token='$TOKEN 'PowerTestV4.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3089025?token='$TOKEN 'Pocahontas_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3022791?token='$TOKEN 'ovealbedo_ANIMA_V1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3007002?token='$TOKEN 'orihime_anima_v09-000007.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3054352?token='$TOKEN 'NewSupergirlAnima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2858862?token='$TOKEN 'MitsuriKanroji_AnimaPreview3_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2900188?token='$TOKEN 'MayAnimePokemon_ANIMA.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2905758?token='$TOKEN 'm44aaffMKMDdsfs465 - Anima_Marin Kitagawa-000007.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3018256?token='$TOKEN 'Lucyna Kushinada Anima v3.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2983480?token='$TOKEN 'kusuriya-maomao-s1-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2971759?token='$TOKEN 'KonanShippuden_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3040406?token='$TOKEN 'JN_Nene_Fujinoki_Anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3054177?token='$TOKEN 'JN_Miyajima_Tsubaki_Anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3078943?token='$TOKEN 'JN_Lily_Ramses_Futaba_Anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2945358?token='$TOKEN 'JessicaRabbit_AnimaV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3026343?token='$TOKEN 'Jeong Soo Ah Anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2948828?token='$TOKEN 'InoYamanakaShippuden_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2995004?token='$TOKEN 'HolliWDG_Anima_V2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2992553?token='$TOKEN 'high-elf-archer-s2-v2-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2817003?token='$TOKEN 'FBJE_laufenANIMA001.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2912022?token='$TOKEN 'Emilia-Anima-v1-08.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3008990?token='$TOKEN 'dbz-videl-anime-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2980419?token='$TOKEN 'asuka-langley-souryuu-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3089805?token='$TOKEN 'Ariel_AnimaBaseV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2970572?token='$TOKEN 'Anzu_MazakiDSOD.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3016136?token='$TOKEN 'anima-v1-character-aratonagi_v2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3059359?token='$TOKEN 'almondeye_anima_v2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2974600?token='$TOKEN '36M3EZSRA97J0CJ01MS07CH520.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2974453?token='$TOKEN '03PRSX1HQSKQ8XMT7PC36RCS70.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2992727?token='$TOKEN 'yor-briar-s1-v2-anima-lora-nochekaiser.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3016724?token='$TOKEN 'Wednesday Addams v2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2946207?token='$TOKEN 'Tsunade_AnimaV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2946268?token='$TOKEN 'TatsumakiMurataStyle_AnimaV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2946245?token='$TOKEN 'SakuraHarunoShippuden_AnimaV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2980149?token='$TOKEN 'MakimaTest.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2963822?token='$TOKEN 'LoRAKugisakiNobaraAnimav1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2946226?token='$TOKEN 'HinataTheLast_AnimaV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2946179?token='$TOKEN 'HinataGenin_AnimaV10_byKonan.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2705225?token='$TOKEN 'ChelDorado_ANIMA.safetensors' "$MODELS_DIR/loras"

# ==========================================
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
# ==========================================
