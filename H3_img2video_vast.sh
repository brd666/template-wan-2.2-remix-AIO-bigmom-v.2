#!/bin/bash
set -o pipefail

# ==========================================================================
# MiniMax H3 img2video (воркфлоу "DaSiWa MiniMaxH3 MythicAlchemy C-MMH3-33")
# Vast.ai provisioning-скрипт (шаблон ComfyUI, Ubuntu 22/24, /workspace/ComfyUI)
# ЭТОТ ФАЙЛ: профиль по умолчанию big — RTX PRO 6000 / H100 / H200 (80–96 ГБ). Для RTX 5090: H3_vast_5090_32GB.sh
#
# Как использовать:
#   1. Создать шаблон Vast на образе  vastai/comfy:v0.44.0-cuda-13.2-py312  (там уже torch под CUDA 13.2,
#      ComfyUI в /workspace/ComfyUI, venv /venv/main, supervisor-программа comfyui).
#   2. Залить этот файл в GitHub (raw-ссылка) и указать её в env шаблона:
#        PROVISIONING_SCRIPT=https://raw.githubusercontent.com/<you>/<repo>/main/<имя этого файла>.sh
#      Рядом положить воркфлоу (.json) и задать WORKFLOW_URL — тогда он сам окажется в ComfyUI.
#   3. Подбирать инстанс по фильтрам (см. ниже). Скрипт сам проверит железо и
#      остановится ДО скачивания моделей, если инстанс не подходит (в т.ч. если профиль не для этой карты).
#   4. На первом запуске ComfyUI стартует сам, когда скрипт закончится (скрипт запуска образа ждёт
#      файла /.provisioning), поэтому перезапуск не нужен. Лог провижининга: /var/log/portal/provisioning.log
#
# ПРОФИЛИ (H3_PROFILE) — два файла отличаются только этой строкой по умолчанию:
#   5090  RTX 5090 (32 ГБ). DiT int8: DaSiWa Hybrid v4 Turbo и обычная, текстовый энкодер nvfp4 (15,7 ГБ).
#         Диск >= 150 ГБ (скрипт требует >= 100 свободных).
#   big   карты 80–96 ГБ (RTX PRO 6000, H100, H200). Те же DaSiWa int8 (они не медленнее bf16 и почти не
#         уступают по качеству), плюс текстовый энкодер int8_convrot (27 ГБ), опция bf16-DiT (H3_BF16_DIT=1,
#         40 ГБ — для сравнения качества). Диск >= 200 ГБ (скрипт требует >= 130 свободных, с bf16 — 170).
#
# Фильтры поиска инстанса на Vast (проверять в карточке оффера):
#   RAM инстанса (cpu_ram): >= 96 ГБ (минимум 64 ГБ, см. подсказку про --disable-pinned-memory)
#   CUDA / драйвер: CUDA >= 13.2 (образ -cuda-13.2) — для pytorch на CUDA 13 и int8_convrot
#
# Переменные окружения (необязательные):
#   H3_PROFILE=5090           5090 | big (см. выше)
#   H3_TE_INT8=               1 = скачать текстовый энкодер int8_convrot (27 ГБ); по умолчанию 0 для 5090, 1 для big
#   H3_BF16_DIT=0             1 = официальная FL2VA pruned bf16 (40 ГБ), только для big
#   ALLOW_PROFILE_MISMATCH=0  1 = не останавливаться, если профиль big запущен на карте < 70 ГБ
#   COMFY_VERSION=v0.44.2     тег ядра ComfyUI
#   CIVITAI_TOKEN=            ТОКЕН CivitAI (обязателен для DaSiWa Hybrid v4 Turbo — модель по умолчанию в воркфлоу;
#                             задать в env шаблона Vast, в логах и в скрипте токен не печатается)
#   H3_DASIWA_REGULAR=1       качать ОБЫЧНУЮ (не turbo) DaSiWa Hybrid v4 int8 (20,5 ГБ): 20–25 шагов, для финального качества
#   H3_DIRECTOR_IMAGE_INPUT=1 добавить узлу MiniMaxH3 Director вход IMAGE (external_image_overwrite): первый кадр I2VA/FL2VA
#                             берётся с любой ноды-загрузчика (например, Load Image Batch From Dir); 0 = не патчить
#   H3_OFFICIAL_FL2VA=0       1 = ещё и официальную FL2VA pruned int8 (21 ГБ) + turbo-LoRA на 4 и 8 шагов (для сравнения)
#   H3_REF2VA=0               1 = ещё и официальную REF2VA pruned int8 (21 ГБ) + turbo-LoRA для неё
#   H3_OPTIONAL=1             апскейлер латента, RIFE, TAE-превью, 2x-AnimeSharpV4 (апскейл моделью); 0 = пропустить
#   TORCH_SWAP=0              1 = если torch в образе НЕ на CUDA 13 — заменить на cu130 той же версии (по умолчанию не трогаем)
#   H3_SELFTEST=1             в конце загрузить все ноды отдельным процессом и показать ошибки импорта
#   UNPIN_NODES=0             1 = ставить ноды из последнего main, а не по зафиксированным коммитам
#   REQUIRE_CUDA13=0          1 = остановиться, если драйвер инстанса поддерживает CUDA < 13.0
#   ALLOW_LOW_DISK=0          1 = не останавливаться при нехватке места
#   WORKFLOW_URL=             прямая ссылка на .json воркфлоу (скачается в user/default/workflows; %20 в имени раскодируется)
#
# Файлы моделей и размеры сверены с HuggingFace 2026-11-08; DaSiWa Hybrid v4 Turbo — CivitAI, версия 3392061,
# файл dasiwa_minimax_h3_ref2va_v4_pruned_turbo_int8.safetensors (проверка по sha256 из API CivitAI).
# DaSiWa Hybrid — один файл на оба слота модели: он умеет и режимы «от изображения» (I2VA, T2VA, L2VA, FL2VA),
# и REF2VA (референсы). Суффикс «int8» в имени файла — способ сжатия весов (8 бит), это не другая модель.
# Turbo — дистиллят на 4–8 шагов (быстро, для черновиков), обычная — 20–25 шагов (для финала).
# Дополнительно (для другого воркфлоу): текстовый энкодер Qwen3-VL 4B fp8 scaled (5,2 ГБ, Comfy-Org/Qwen3-VL) —
# нужен узлу Load CLIP с типом qwen_image; кладётся в models/text_encoders.
# Ноды (кроме Manager, KJNodes, GGUF, DaSiWa): rgthree, Impact Pack, Inspire Pack, Easy Use, DynamicPrompts,
# WAS Node Suite (Revised) — для блока «картинка → промпт» (Prompt enhancer, загрузка картинок из папки).
# Воркфлоу «MythicAlchemy» по умолчанию выбирает в панели Settings: DaSiWa Hybrid v4 Turbo в обоих слотах UNET,
# video VAE int8_convrot, CLIP nvfp4_awq, audio VAE fp32 — всё это скачивается ниже, менять списки не придётся.
# ВАЖНО: скрипт проверен только синтаксически и по ссылкам/версиям; на живом
# инстансе Vast его ещё не запускали.
# ==========================================================================

H3_REF2VA="${H3_REF2VA:-0}"
H3_OFFICIAL_FL2VA="${H3_OFFICIAL_FL2VA:-0}"
H3_DASIWA_REGULAR="${H3_DASIWA_REGULAR:-1}"
H3_DIRECTOR_IMAGE_INPUT="${H3_DIRECTOR_IMAGE_INPUT:-1}"
CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
H3_OPTIONAL="${H3_OPTIONAL:-1}"
UNPIN_NODES="${UNPIN_NODES:-0}"
REQUIRE_CUDA13="${REQUIRE_CUDA13:-0}"
TORCH_SWAP="${TORCH_SWAP:-0}"
H3_SELFTEST="${H3_SELFTEST:-1}"
ALLOW_LOW_DISK="${ALLOW_LOW_DISK:-0}"
COMFY_VERSION="${COMFY_VERSION:-v0.44.2}"
WORKFLOW_URL="${WORKFLOW_URL:-}"
ALLOW_PROFILE_MISMATCH="${ALLOW_PROFILE_MISMATCH:-0}"

# Профиль железа: 5090 (32 ГБ) или big (80–96 ГБ). Файл H3_vast_80-96GB.sh отличается от H3_vast_5090_32GB.sh только этой строкой.
H3_PROFILE="${H3_PROFILE:-big}"
case "$H3_PROFILE" in
    5090) H3_TE_INT8="${H3_TE_INT8:-0}"; H3_BF16_DIT="${H3_BF16_DIT:-0}" ;;
    big)  H3_TE_INT8="${H3_TE_INT8:-1}"; H3_BF16_DIT="${H3_BF16_DIT:-0}" ;;
    *) echo "❌ H3_PROFILE должен быть 5090 или big (сейчас: $H3_PROFILE)" >&2; exit 1 ;;
esac
if [ "$H3_PROFILE" = "5090" ] && [ "$H3_BF16_DIT" = "1" ]; then
    echo "⚠️ bf16-модель (40 ГБ) не помещается в 32 ГБ — H3_BF16_DIT отключён для профиля 5090." >&2
    H3_BF16_DIT=0
fi
# минимум свободного места на диске: база 100 ГБ (+30 за энкодер int8, +40 за bf16-модель)
MIN_DISK_GB=100
[ "$H3_TE_INT8" = "1" ] && MIN_DISK_GB=$((MIN_DISK_GB+30))
[ "$H3_BF16_DIT" = "1" ] && MIN_DISK_GB=$((MIN_DISK_GB+40))

export PIP_NO_CACHE_DIR=1
export DEBIAN_FRONTEND=noninteractive
START_TS=$SECONDS

# сравнение версий: ver_ge A B  -> истина, если A >= B
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# profile_check ПРОФИЛЬ VRAM_МиБ: 0 = подходит, 1 = профиль не для этой карты (причина в stderr)
profile_check() {
    local prof="$1" vram="$2"
    [[ "$vram" =~ ^[0-9]+$ ]] || return 0
    if [ "$prof" = "big" ] && [ "$vram" -lt 70000 ]; then
        echo "❌ Профиль big рассчитан на карты 80+ ГБ (PRO 6000, H100, H200), а здесь ${vram} МиБ VRAM." >&2
        echo "   Для RTX 5090 (32 ГБ) возьми профиль 5090 (H3_PROFILE=5090): там модели подобраны под 32 ГБ." >&2
        return 1
    fi
    if [ "$prof" = "5090" ] && [ "$vram" -lt 30000 ]; then
        echo "⚠️ VRAM ${vram} МиБ < 30000: pruned-int8 модель (21 ГБ) пойдёт с выгрузкой весов, будет заметно медленнее." >&2
    fi
    return 0
}

# --------------------------------------------------------------------------
# 0. PREFLIGHT: железо проверяем до трат времени и денег
# --------------------------------------------------------------------------
echo "🔍 Preflight: проверяю инстанс..."
mkdir -p /opt/da

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "❌ nvidia-smi не найден — это не GPU-инстанс или драйвер не встал." >&2
    exit 1
fi
if ! nvidia-smi -L >/dev/null 2>&1; then
    echo "❌ nvidia-smi не смог опросить карту. Уничтожь инстанс и возьми другой хост." >&2
    exit 1
fi
RECOVERY_ACTION=$(nvidia-smi --query-gpu=gpu_recovery_action --format=csv,noheader 2>/dev/null | tr -d '[:space:]')
if [ -n "$RECOVERY_ACTION" ] && [ "$RECOVERY_ACTION" != "None" ] && [ "$RECOVERY_ACTION" != "N/A" ]; then
    echo "❌ GPU просит recovery action: $RECOVERY_ACTION — это состояние хоста, изнутри не чинится." >&2
    exit 1
fi
PY_PROBE=python3; command -v "$PY_PROBE" >/dev/null 2>&1 || PY_PROBE=python
if command -v "$PY_PROBE" >/dev/null 2>&1; then
    "$PY_PROBE" - <<'PYEOF'
import ctypes, sys
try:
    rc = ctypes.CDLL("libcuda.so.1").cuInit(0)
except OSError:
    sys.exit(0)
if rc != 0:
    print(f"cuInit вернул {rc} — CUDA-контекст не создаётся", file=sys.stderr)
    sys.exit(1)
PYEOF
    if [ $? -ne 0 ]; then
        echo "❌ CUDA не инициализируется при живом nvidia-smi — GPU в нерабочем состоянии." >&2
        exit 1
    fi
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '[:space:]')
CUDA_VER=$(nvidia-smi 2>/dev/null | grep -o 'CUDA Version: *[0-9][0-9.]*' | head -1 | awk '{print $NF}')
echo "   GPU: ${GPU_NAME:-?} | VRAM: ${VRAM_MB:-?} МиБ | CUDA драйвера: ${CUDA_VER:-?}"

# ОЗУ: берём меньшее из MemTotal и лимита cgroup (в контейнере Vast лимит бывает ниже)
RAM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
for CG in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
    if [ -r "$CG" ]; then
        V=$(cat "$CG" 2>/dev/null)
        if [[ "$V" =~ ^[0-9]+$ ]] && [ $((V/1024)) -lt "${RAM_KB:-0}" ]; then RAM_KB=$((V/1024)); fi
    fi
done
RAM_GB=$(( ${RAM_KB:-0} / 1024 / 1024 ))
echo "   ОЗУ: ${RAM_GB} ГБ"

# 0a. VRAM и профиль
echo "   Профиль: $H3_PROFILE"
if ! profile_check "$H3_PROFILE" "$VRAM_MB"; then
    [ "$ALLOW_PROFILE_MISMATCH" = "1" ] || exit 1
    echo "   ALLOW_PROFILE_MISMATCH=1 — продолжаю на свой риск." >&2
fi
if [ "$H3_PROFILE" = "5090" ] && [[ "$VRAM_MB" =~ ^[0-9]+$ ]] && [ "$VRAM_MB" -ge 70000 ]; then
    echo "ℹ️ На карте ${VRAM_MB} МиБ есть смысл взять профиль big (H3_PROFILE=big): энкодер int8 и опция bf16." >&2
fi

# 0b. ОЗУ
if [ "$RAM_GB" -lt 60 ]; then
    echo "⚠️ ОЗУ ${RAM_GB} ГБ < 60: на H3 часто падает по памяти. Рекомендуется >= 96 ГБ." >&2
elif [ "$RAM_GB" -lt 80 ]; then
    echo "ℹ️ ОЗУ ${RAM_GB} ГБ: хватает, но впритык. Если ComfyUI убивает по памяти — добавь --disable-pinned-memory в COMFYUI_ARGS." >&2
fi

# 0c. CUDA
CUDA13_OK=0
if [ -n "$CUDA_VER" ] && ver_ge "$CUDA_VER" "13.0"; then
    CUDA13_OK=1
else
    echo "⚠️ CUDA драйвера: ${CUDA_VER:-неизвестна} (< 13.0). Для int8_convrot рекомендован pytorch cu130 (драйвер >= 580)." >&2
    echo "   На cu128 модели могут работать медленнее. Надёжнее взять другой инстанс (фильтр CUDA >= 13.0)." >&2
    if [ "$REQUIRE_CUDA13" = "1" ]; then
        echo "❌ REQUIRE_CUDA13=1 — останавливаюсь." >&2
        exit 1
    fi
fi
echo "✅ Preflight пройден."

# --------------------------------------------------------------------------
# 1. ПУТИ И PYTHON
# --------------------------------------------------------------------------
if [ -f "/venv/main/bin/python" ]; then
    PY_EXEC="/venv/main/bin/python"
    PIP_EXEC="/venv/main/bin/python -m pip"
    EXTRA_PIP_FLAGS=""
    echo "✅ Найден venv python: $PY_EXEC"
else
    PY_EXEC="python3"
    PIP_EXEC="python3 -m pip"
    EXTRA_PIP_FLAGS=""
    if python3 -c "import sys; print(sys.version_info >= (3, 11))" | grep -q "True"; then
        EXTRA_PIP_FLAGS="--break-system-packages"
    fi
    echo "⚠️ Используем системный python3 $EXTRA_PIP_FLAGS"
fi

if ! $PIP_EXEC --version >/dev/null 2>&1; then
    echo "⚠️ pip в окружении не найден — ставлю через ensurepip..."
    $PY_EXEC -m ensurepip --upgrade || { echo "❌ не удалось получить pip" >&2; exit 1; }
fi

if [ -d "/workspace/ComfyUI" ]; then
    COMFY_DIR="/workspace/ComfyUI"
elif [ -n "${COMFYUI_PATH:-}" ] && [ -d "${COMFYUI_PATH}" ]; then
    COMFY_DIR="${COMFYUI_PATH}"
elif [ -d "/opt/ComfyUI" ]; then
    COMFY_DIR="/opt/ComfyUI"
else
    echo "❌ ComfyUI не найден (проверены /workspace/ComfyUI, \$COMFYUI_PATH, /opt/ComfyUI)." >&2
    echo "   Задай COMFYUI_PATH в env инстанса Vast либо проверь образ шаблона." >&2
    exit 1
fi
echo "📁 ComfyUI: $COMFY_DIR"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

# 1a. Место на диске — до скачивания, а не после
DISK_FREE_GB=$(df -Pk "$COMFY_DIR" 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}')
echo "   Свободно на диске: ${DISK_FREE_GB:-?} ГБ (нужно >= $MIN_DISK_GB)"
if [ -n "$DISK_FREE_GB" ] && [ "$DISK_FREE_GB" -lt "$MIN_DISK_GB" ]; then
    echo "❌ Мало места: ${DISK_FREE_GB} ГБ, для профиля $H3_PROFILE нужно не меньше ${MIN_DISK_GB} ГБ (модели + torch/venv). Подними размер диска при аренде." >&2
    [ "$ALLOW_LOW_DISK" = "1" ] || exit 1
    echo "   ALLOW_LOW_DISK=1 — продолжаю на свой риск." >&2
fi

# --------------------------------------------------------------------------
# 2. СИСТЕМНЫЕ УТИЛИТЫ
# --------------------------------------------------------------------------
echo "⚙️ Установка системных утилит..."
for _ in 1 2 3; do
    apt-get update --fix-missing && break || (echo "Retry apt-get update..." && sleep 5)
done
apt-get install -y ffmpeg libgl1 libglx-mesa0 wget git

# --------------------------------------------------------------------------
# 3. PYTORCH: образ vastai/comfy:*-cuda-13.2-* уже содержит torch под CUDA 13 — его не трогаем
# --------------------------------------------------------------------------
echo "💊 Базовые библиотеки Python..."
$PIP_EXEC install --upgrade pip $EXTRA_PIP_FLAGS

TORCH_NOW=$($PY_EXEC -c "import torch; print(torch.__version__)" 2>/dev/null)
TORCH_CUDA=$($PY_EXEC -c "import torch; print(torch.version.cuda or '')" 2>/dev/null)
echo "   torch: ${TORCH_NOW:-не установлен} (собран под CUDA ${TORCH_CUDA:-?})"
case "$TORCH_NOW" in
    *+cu13*)
        echo "   ✅ torch на CUDA 13 — менять не нужно."
        ;;
    *)
        echo "⚠️ torch не на CUDA 13. Для int8_convrot рекомендован образ vastai/comfy:...-cuda-13.2-py312." >&2
        if [ "$TORCH_SWAP" = "1" ] && [ "$CUDA13_OK" = "1" ] && [ -n "$TORCH_NOW" ]; then
            TORCH_BASE="${TORCH_NOW%%+*}"
            echo "   ⬇️ TORCH_SWAP=1: ставлю torch==$TORCH_BASE (cu130) с подходящими torchvision/torchaudio..."
            $PIP_EXEC install $EXTRA_PIP_FLAGS "torch==$TORCH_BASE" torchvision torchaudio \
                --index-url https://download.pytorch.org/whl/cu130 \
                || echo "   ⚠️ замена torch не удалась — остаюсь на torch из образа." >&2
        fi
        ;;
esac
# Драйвер должен поддерживать ту CUDA, под которую собран torch
if [ -n "$TORCH_CUDA" ] && [ -n "$CUDA_VER" ] && ! ver_ge "$CUDA_VER" "$TORCH_CUDA"; then
    echo "⚠️ Драйвер хоста поддерживает CUDA $CUDA_VER, а torch собран под $TORCH_CUDA — возможны ошибки. Надёжнее взять другой инстанс." >&2
fi
# Фиксируем версии torch, чтобы зависимости нод не подменили сборку
$PIP_EXEC freeze 2>/dev/null | grep -i -E '^(torch|torchvision|torchaudio)==' > /opt/da/constraints.txt
echo "   Констрейнты:"; sed 's/^/     /' /opt/da/constraints.txt

# --------------------------------------------------------------------------
# 4. ЯДРО ComfyUI: фиксируем версию (иначе версия из образа может не совпасть)
# --------------------------------------------------------------------------
case "$COMFY_VERSION" in
    v*) COMFY_VERSION_ALT="${COMFY_VERSION#v}" ;;
    *)  COMFY_VERSION_ALT="v$COMFY_VERSION" ;;
esac
echo "📌 Ставлю ComfyUI $COMFY_VERSION (сейчас: $(cd "$COMFY_DIR" && git describe --tags --always 2>/dev/null || echo неизвестна))"
COMFY_PINNED=""
(cd "$COMFY_DIR" && git fetch --tags --force origin) || echo "   ⚠️ git fetch не удался — пробую то, что есть локально" >&2
for TAG in "$COMFY_VERSION" "$COMFY_VERSION_ALT"; do
    if (cd "$COMFY_DIR" && git checkout --force "$TAG") >/dev/null 2>&1; then COMFY_PINNED="$TAG"; break; fi
done
if [ -z "$COMFY_PINNED" ]; then
    if (cd "$COMFY_DIR" && git fetch --depth 1 --force origin "refs/tags/$COMFY_VERSION:refs/tags/$COMFY_VERSION" && git checkout --force "$COMFY_VERSION") >/dev/null 2>&1; then
        COMFY_PINNED="$COMFY_VERSION"
    fi
fi
if [ -z "$COMFY_PINNED" ]; then
    echo "❌ Не удалось переключить ComfyUI на $COMFY_VERSION." >&2
    echo "   Ноды и воркфлоу собраны под эту версию ядра — останавливаюсь." >&2
    exit 1
fi
echo "   📦 Зависимости ядра (frontend и kitchen пиннятся в requirements.txt)..."
(cd "$COMFY_DIR" && $PIP_EXEC install $EXTRA_PIP_FLAGS -c /opt/da/constraints.txt -r requirements.txt) \
    || echo "   ⚠️ requirements.txt поставился не полностью — проверь лог выше" >&2
echo "✅ ComfyUI зафиксирован на $COMFY_PINNED"

# --------------------------------------------------------------------------
# 5. CUSTOM NODES (по коммитам, проверенным 2026-11-08)
# --------------------------------------------------------------------------
mkdir -p "$NODES_DIR"
cd "$NODES_DIR" || exit 1

NODES_TOTAL=10
NODES_DONE=0
FAILED_NODES=()

# install_node URL DIR PIN_SHA [REGEX_ИСКЛЮЧИТЬ_ИЗ_requirements]
install_node() {
    local REPO_URL="$1" DIR_NAME="$2" PIN="$3" EXCLUDE="$4"
    NODES_DONE=$((NODES_DONE+1))
    echo "🔧 [$NODES_DONE/$NODES_TOTAL] Нода: $DIR_NAME"
    if [ ! -d "$DIR_NAME/.git" ]; then
        rm -rf "$DIR_NAME"
        echo "   ⬇️ Клонирование..."
        if ! git clone --depth 1 "$REPO_URL" "$DIR_NAME"; then
            echo "   ❌ $DIR_NAME: clone не удался" >&2
            FAILED_NODES+=("$DIR_NAME")
            return 1
        fi
    fi
    if [ -n "$PIN" ] && [ "$UNPIN_NODES" != "1" ]; then
        if (cd "$DIR_NAME" && git fetch --depth 1 --force origin "$PIN" && git checkout --force FETCH_HEAD) >/dev/null 2>&1; then
            echo "   📌 $DIR_NAME → ${PIN:0:10}"
        else
            echo "   ⚠️ $DIR_NAME: коммит $PIN не найден — остаюсь на последнем main" >&2
        fi
    fi
    if [ -f "$DIR_NAME/requirements.txt" ]; then
        echo "   📦 Зависимости $DIR_NAME..."
        local TMP_REQ; TMP_REQ=$(mktemp)
        if [ -n "$EXCLUDE" ]; then
            grep -v -i -E "$EXCLUDE" "$DIR_NAME/requirements.txt" > "$TMP_REQ"
        else
            cp "$DIR_NAME/requirements.txt" "$TMP_REQ"
        fi
        $PIP_EXEC install $EXTRA_PIP_FLAGS -c /opt/da/constraints.txt -r "$TMP_REQ" \
            || echo "   ⚠️ $DIR_NAME: зависимости поставились не полностью" >&2
        rm -f "$TMP_REQ"
    fi
}

install_node 'https://github.com/Comfy-Org/ComfyUI-Manager'            'ComfyUI-Manager'      '4c50a2bc8b9e684d8a85930567957470b952bebe' ''
install_node 'https://github.com/kijai/ComfyUI-KJNodes'                'ComfyUI-KJNodes'      'ab72eda7ffad6280422d71ab7d54d3fb87c0ba18' ''
install_node 'https://github.com/city96/ComfyUI-GGUF'                  'ComfyUI-GGUF'         '6ea2651e7df66d7585f6ffee804b20e92fb38b8a' ''
# DaSiWa: llama-cpp-python (Prompt Forge с локальной GGUF-моделью) собирается из исходников и
# воркфлоу для генерации не нужен; nvidia-vfx и amd-adlx ставим отдельно/не ставим.
install_node 'https://github.com/darksidewalker/ComfyUI-DaSiWa-Nodes'  'ComfyUI-DaSiWa-Nodes' 'c52b1704d8250d1205515f1ce39c5d6c9ed9cd32' '^(llama-cpp-python|nvidia-vfx|amd-adlx)'

# Патч Director: у узла нет входа для картинки (только размер и промпт), кадр выбирают вручную в его панели.
# Добавляем вход IMAGE «external_image_overwrite»: первый кадр I2VA/FL2VA берётся с любой ноды-загрузчика
# (например, Load Image Batch From Dir), и всё можно гонять автоматом. Без подключённого входа узел работает как раньше.
# H3_DIRECTOR_IMAGE_INPUT=0 отключает патч; если фрагменты кода не найдены, патч пропускается без последствий.
if [ "$H3_DIRECTOR_IMAGE_INPUT" = "1" ]; then
    echo "   🖼️ Director: добавляю вход IMAGE для первого кадра..."
    $PY_EXEC - "$NODES_DIR/ComfyUI-DaSiWa-Nodes/nodes/nodes_minimax_h3_director.py" <<'PYEOF' || echo "   ⚠️ патч Director не применён — первый кадр придётся выбирать в панели Director вручную" >&2
import sys

# Добавляет в узел MiniMaxH3 Director (ComfyUI-DaSiWa-Nodes) необязательный входной сокет IMAGE
# «external_image_overwrite»: картинка с сокета становится первым кадром в режимах I2VA и FL2VA
# (как external_width/height/prompt_overwrite заменяют размер и промпт). Без подключённого сокета узел
# работает как раньше. Повторный запуск безопасен. Использование: python h3_director_image_patch.py <путь к nodes_minimax_h3_director.py>

path = sys.argv[1]
s = open(path, encoding="utf-8", newline="").read()
if "external_image_overwrite" in s:
    print("   ✅ патч Director уже применён")
    sys.exit(0)
if "\r" in s:
    print("   ⚠️ файл с CRLF — патч не применяю", file=sys.stderr)
    sys.exit(1)

edits = [
    # 1. входной сокет
    ('''                "external_prompt_overwrite": ("STRING", {"default": "", "multiline": True, "forceInput": True}),
''',
     '''                "external_prompt_overwrite": ("STRING", {"default": "", "multiline": True, "forceInput": True}),
                "external_image_overwrite": ("IMAGE", {"forceInput": True,
                    "tooltip": "First frame for I2VA/FL2VA from another node (e.g. Load Image Batch From Dir). Replaces the image chosen in the Director panel."}),
''', 1),
    # 2. параметр в check_lazy_status и build_guide (в конец списка, чтобы не сдвигать позиционные аргументы)
    ("external_prompt_overwrite=None, frame_rate=24.0):",
     "external_prompt_overwrite=None, frame_rate=24.0, external_image_overwrite=None):", 2),
    # 3. логика: после разбора картинок из панели, до сборки тегов
    ('''        tag_map = _refmod_tag_map(refmod_items, ref_images, ref_videos, ref_video_audios, ref_audios)
''',
     '''        if external_image_overwrite is not None and not continuing and mode in ("I2VA", "FL2VA"):
            external_frame = external_image_overwrite
            if hasattr(external_frame, "shape") and len(external_frame.shape) == 4:
                external_frame = external_frame[:1]
            first_frame = scale_input_media(external_frame, input_scaling, width, height)

        tag_map = _refmod_tag_map(refmod_items, ref_images, ref_videos, ref_video_audios, ref_audios)
''', 1),
]
for old, new, count in edits:
    if s.count(old) != count:
        print(f"   ⚠️ не найден ожидаемый фрагмент ({s.count(old)} из {count}): {old.strip()[:70]}", file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new)
try:
    compile(s, path, "exec")
except SyntaxError as exc:
    print(f"   ⚠️ после патча файл не компилируется: {exc}", file=sys.stderr)
    sys.exit(1)
open(path, "w", encoding="utf-8", newline="").write(s)
print("   ✅ Director: добавлен вход external_image_overwrite (IMAGE)")
PYEOF
fi

# Ноды для блока «картинка → промпт» (список из ComfyUI-Manager → Install Missing Custom Nodes).
# Impact Pack ставим раньше Inspire Pack: тот его импортирует.
# Из requirements исключены: sam2 (сборка из исходников тянет второй torch; без него Impact Pack лишь пишет
# предупреждение, SAM2-узлы воркфлоу не нужны), fairscale (нужен только старому модулю BLIP в WAS; BLIP-узлы WAS
# работают через transformers) и opencv-python (уже есть opencv-python-headless; два пакета cv2 мешают друг другу).
# У WAS убраны и три зависимости из git (img2texture, cstr, ffmpy): setup.py форка ffmpy импортирует удалённый
# setuptools.command.test и не собирается, а один такой сбой ронял бы установку всех остальных зависимостей WAS.
# Основному коду WAS они не нужны (img2texture он докачивает сам, когда запускается соответствующий узел).
install_node 'https://github.com/rgthree/rgthree-comfy'            'rgthree-comfy'          'bc48c6aaeca87bedbc14245d89f9bc6be37a630e' ''
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Pack'     'ComfyUI-Impact-Pack'    'eace4a9059908330936c6514f35f5e0c84935394' '^git\+https://github\.com/facebookresearch/sam2'
install_node 'https://github.com/ltdrdata/ComfyUI-Inspire-Pack'    'ComfyUI-Inspire-Pack'   'd23db9aa544de9a6d4c609cb7005fa9e0d42031d' '^opencv-python[[:space:]]*$'
install_node 'https://github.com/yolain/ComfyUI-Easy-Use'          'ComfyUI-Easy-Use'       'b0b47ca1372117fce575d9e744655344ebff6bef' ''
install_node 'https://github.com/adieyal/comfyui-dynamicprompts'   'comfyui-dynamicprompts'  '0cda22b2cb4e71ade4c748d0f0e23b3b17be4ebd' ''
install_node 'https://github.com/ltdrdata/was-node-suite-comfyui'  'was-node-suite-comfyui'  '44de705818d4663fefefde57ffe0ea5a9ea39df4' '^(fairscale|git\+)'

echo "   🎞️ nvidia-vfx (нужен только для опциональных RTX-узлов, индекс NVIDIA)..."
$PIP_EXEC install $EXTRA_PIP_FLAGS -c /opt/da/constraints.txt nvidia-vfx --extra-index-url https://pypi.nvidia.com/ \
    || echo "   ⚠️ nvidia-vfx не поставился — RTX-апскейл/интерполяция в воркфлоу будут недоступны (по умолчанию они выключены)" >&2

echo "🧪 Проверка torch..."
$PY_EXEC - <<'PYEOF'
import torch
ok = torch.cuda.is_available()
print(f"   torch {torch.__version__} | cuda_available={ok} | {torch.cuda.get_device_name(0) if ok else '-'}")
PYEOF

# --------------------------------------------------------------------------
# 6. МОДЕЛИ (wget -c, докачка; проверка точного размера или sha256)
#    Имена и подпапки совпадают с теми, что записаны в воркфлоу.
# --------------------------------------------------------------------------
echo "⬇️ Скачивание моделей (профиль $H3_PROFILE)..."
HF_H3="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main"
DASIWA_SHA="36471AFB817747B711B9ABAD3D8E6B7C88A7C2B91B4887D040A8DCB7EE82B2D6"            # v4 Turbo int8
DASIWA_REGULAR_SHA="4AD2A1D7135C77F799BA9B93AF893FC2654315408C069A26F6516CDED1E8A53B"    # v4 обычная int8
FAILED_MODELS=()

# формат: URL | путь внутри папки | папка в models | размер в байтах (0 = не проверять) | sha256 (необязательно)
MODEL_LIST=()
if [ -n "$CIVITAI_TOKEN" ]; then
  MODEL_LIST+=("https://civitai.com/api/download/models/3392061?fileId=3281858|MiniMaxH3/dasiwa_minimax_h3_ref2va_v4_pruned_turbo_int8.safetensors|$MODELS_DIR/diffusion_models|0|$DASIWA_SHA")
  if [ "$H3_DASIWA_REGULAR" = "1" ]; then
    MODEL_LIST+=("https://civitai.com/api/download/models/3391862?fileId=3281578|MiniMaxH3/dasiwa_minimax_h3_ref2va_v4_pruned_int8.safetensors|$MODELS_DIR/diffusion_models|0|$DASIWA_REGULAR_SHA")
  fi
else
  echo "⚠️ CIVITAI_TOKEN не задан — модели DaSiWa Hybrid v4 (CivitAI) пропущены, воркфлоу по умолчанию без них не запустится." >&2
  echo "   Задай CIVITAI_TOKEN в env шаблона Vast либо поставь H3_OFFICIAL_FL2VA=1 и выбери официальную FL2VA в панели Settings." >&2
  FAILED_MODELS+=("MiniMaxH3/dasiwa_minimax_h3_ref2va_v4_pruned_turbo_int8.safetensors (нужен CIVITAI_TOKEN)")
  [ "$H3_DASIWA_REGULAR" = "1" ] && FAILED_MODELS+=("MiniMaxH3/dasiwa_minimax_h3_ref2va_v4_pruned_int8.safetensors (нужен CIVITAI_TOKEN)")
fi
MODEL_LIST+=(
  "$HF_H3/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors|qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors|$MODELS_DIR/text_encoders|15687142551|"
  "$HF_H3/vae/minimax_h3_video_vae_fp16.safetensors|MiniMaxH3/minimax_h3_video_vae_fp16.safetensors|$MODELS_DIR/vae|5207808496|"
  "https://huggingface.co/Kijai/MiniMax-H3-experimental/resolve/main/minimax_h3_video_vae_int8_convrot.safetensors|MiniMaxH3/minimax_h3_video_vae_int8_convrot.safetensors|$MODELS_DIR/vae|3171670912|"
  "$HF_H3/vae/minimax_h3_audio_vae_fp32.safetensors|MiniMaxH3/minimax_h3_audio_vae_fp32.safetensors|$MODELS_DIR/vae|605254808|"
  "https://huggingface.co/Comfy-Org/Qwen3-VL/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors|qwen3vl_4b_fp8_scaled.safetensors|$MODELS_DIR/text_encoders|5242467968|"
)
if [ "$H3_OFFICIAL_FL2VA" = "1" ]; then
  MODEL_LIST+=(
    "$HF_H3/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors|MiniMaxH3/minimax_h3_fl2va_pruned_int8_convrot.safetensors|$MODELS_DIR/diffusion_models|20970379616|"
    "$HF_H3/loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors|MiniMaxH3/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors|$MODELS_DIR/loras|1956192992|"
    "$HF_H3/loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors|MiniMaxH3/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors|$MODELS_DIR/loras|1956193000|"
  )
fi
if [ "$H3_TE_INT8" = "1" ]; then
  MODEL_LIST+=(
    "$HF_H3/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors|qwen3vl_32b_minimax_h3_int8_convrot.safetensors|$MODELS_DIR/text_encoders|27141342152|"
  )
fi
if [ "$H3_BF16_DIT" = "1" ]; then
  MODEL_LIST+=(
    "$HF_H3/diffusion_models/minimax_h3_fl2va_pruned_bf16.safetensors|MiniMaxH3/minimax_h3_fl2va_pruned_bf16.safetensors|$MODELS_DIR/diffusion_models|40225724176|"
  )
fi
if [ "$H3_OPTIONAL" = "1" ]; then
  MODEL_LIST+=(
    "https://huggingface.co/Kijai/MiniMax-H3-TAE/resolve/main/vae_approx/taeh3.safetensors|taeh3.safetensors|$MODELS_DIR/vae_approx|9791388|"
    "https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler/resolve/main/minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_bf16.safetensors|minimax_h3_latent_upscaler_3d_conv_v1_bf16.safetensors|$MODELS_DIR/latent_upscale_models|690592992|"
    "https://huggingface.co/Comfy-Org/frame_interpolation/resolve/main/frame_interpolation/rife_v4.26.safetensors|rife_v4.26.safetensors|$MODELS_DIR/frame_interpolation|22674688|"
    "https://huggingface.co/Kim2091/2x-AnimeSharpV4/resolve/main/2x-AnimeSharpV4_RCAN.safetensors|2x-AnimeSharpV4_RCAN.safetensors|$MODELS_DIR/upscale_models|31053198|"
  )
fi
if [ "$H3_REF2VA" = "1" ]; then
  MODEL_LIST+=(
    "$HF_H3/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors|MiniMaxH3/minimax_h3_ref2va_pruned_int8_convrot.safetensors|$MODELS_DIR/diffusion_models|20970379616|"
    "$HF_H3/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors|MiniMaxH3/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors|$MODELS_DIR/loras|1956193000|"
  )
fi

MODELS_TOTAL=${#MODEL_LIST[@]}
TOTAL_MODELS=0
OK_MODELS=0

# Для CivitAI ссылка с токеном отдаёт редирект на подписанный адрес — его и качаем (без заголовка).
resolve_final_url() {
    local u="$1" loc
    case "$u" in
        *civitai.com/*|*civitai.red/*)
            [ -n "$CIVITAI_TOKEN" ] || return 1
            loc=$(curl -s -o /dev/null -w '%{redirect_url}' -H "Authorization: Bearer $CIVITAI_TOKEN" "$u")
            [ -n "$loc" ] || return 1
            printf '%s' "$loc"
            ;;
        *) printf '%s' "$u" ;;
    esac
}

download_model() {
    local URL="$1" REL="$2" DIR="$3" EXP="$4" SHA="$5"
    local DEST="$DIR/$REL"
    TOTAL_MODELS=$((TOTAL_MODELS+1))
    if [ "$EXP" -gt 0 ] 2>/dev/null; then
        echo "📦 [$TOTAL_MODELS/$MODELS_TOTAL] $REL ($((EXP/1048576)) МБ)"
    else
        echo "📦 [$TOTAL_MODELS/$MODELS_TOTAL] $REL"
    fi
    mkdir -p "$(dirname "$DEST")"

    local CUR; CUR=$(stat -c %s "$DEST" 2>/dev/null || echo 0)
    if [ -n "$SHA" ] && [ -f "$DEST.sha256ok" ] && [ "$CUR" -gt 0 ]; then
        echo "   ✅ уже скачан и проверен по sha256."
        OK_MODELS=$((OK_MODELS+1))
        return 0
    fi
    if [ -z "$SHA" ] && [ "$EXP" -gt 0 ] 2>/dev/null && [ "$CUR" = "$EXP" ]; then
        echo "   ✅ уже скачан, размер совпадает."
        OK_MODELS=$((OK_MODELS+1))
        return 0
    fi
    if [ "$EXP" -gt 0 ] 2>/dev/null && [ "$CUR" -gt "$EXP" ]; then rm -f "$DEST"; fi

    local T0=$SECONDS ATTEMPT=1 MAX_ATTEMPTS=15 RC COMPLETE GOT
    local DL_URL
    while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
        [ "$ATTEMPT" -gt 1 ] && echo "   🔄 докачка, попытка $ATTEMPT/$MAX_ATTEMPTS..."
        if ! DL_URL=$(resolve_final_url "$URL"); then
            echo "   ⚠️ не удалось получить ссылку на скачивание (проверь CIVITAI_TOKEN), попытка $ATTEMPT" >&2
            [ "$ATTEMPT" -ge 3 ] && break
            sleep 5; ATTEMPT=$((ATTEMPT+1)); continue
        fi
        wget --tries=3 --timeout=30 -c --progress=dot:giga "$DL_URL" -O "$DEST"
        RC=$?
        CUR=$(stat -c %s "$DEST" 2>/dev/null || echo 0)
        COMPLETE=0
        if [ -n "$SHA" ]; then
            [ "$RC" -eq 0 ] && [ "$CUR" -gt 0 ] && COMPLETE=1
        elif [ "$EXP" -gt 0 ] 2>/dev/null; then
            [ "$CUR" = "$EXP" ] && COMPLETE=1
        else
            [ "$RC" -eq 0 ] && [ "$CUR" -gt 0 ] && COMPLETE=1
        fi
        if [ "$COMPLETE" = "1" ] && [ -n "$SHA" ]; then
            echo "   🔐 проверяю sha256..."
            GOT=$(sha256sum "$DEST" | awk '{print toupper($1)}')
            if [ "$GOT" = "${SHA^^}" ]; then
                echo "$SHA" > "$DEST.sha256ok"
            else
                echo "   ⚠️ sha256 не совпал ($GOT) — удаляю и качаю заново" >&2
                rm -f "$DEST"; COMPLETE=0
            fi
        fi
        if [ "$COMPLETE" = "1" ]; then
            echo "   ✅ готово за $((SECONDS-T0)) с"
            OK_MODELS=$((OK_MODELS+1))
            return 0
        fi
        if [ "$EXP" -gt 0 ] 2>/dev/null && [ "$CUR" -gt "$EXP" ]; then
            echo "   ⚠️ файл больше ожидаемого ($CUR > $EXP) — удаляю и качаю заново" >&2
            rm -f "$DEST"
        fi
        sleep 5
        ATTEMPT=$((ATTEMPT+1))
    done
    echo "   ❌ НЕ СКАЧАЛОСЬ: $REL (получено ${CUR} байт)" >&2
    AVAIL_KB=$(df -Pk "$DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 2097152 ] 2>/dev/null; then
        echo "   💾 Кончается место на диске (свободно $((AVAIL_KB/1024)) МБ)." >&2
    fi
    FAILED_MODELS+=("$REL")
    return 1
}

for ENTRY in "${MODEL_LIST[@]}"; do
    IFS='|' read -r M_URL M_REL M_DIR M_SIZE M_SHA <<< "$ENTRY"
    download_model "$M_URL" "$M_REL" "$M_DIR" "$M_SIZE" "$M_SHA"
    echo "📊 Моделей: $TOTAL_MODELS/$MODELS_TOTAL обработано (успешно: $OK_MODELS)"
done

# --------------------------------------------------------------------------
# 7. ВОРКФЛОУ (если задана ссылка)
# --------------------------------------------------------------------------
if [ -n "$WORKFLOW_URL" ]; then
    WF_DIR="$COMFY_DIR/user/default/workflows"
    mkdir -p "$WF_DIR"
    WF_NAME=$($PY_EXEC -c 'import sys, os, urllib.parse; print(urllib.parse.unquote(os.path.basename(sys.argv[1].split("?")[0])))' "$WORKFLOW_URL")
    echo "🧾 Воркфлоу: $WF_NAME"
    wget -q --tries=3 --timeout=30 "$WORKFLOW_URL" -O "$WF_DIR/$WF_NAME" \
        && echo "   ✅ сохранён в $WF_DIR" \
        || echo "   ⚠️ воркфлоу не скачался — загрузи .json через интерфейс" >&2
fi

# --------------------------------------------------------------------------
# 8. САМОПРОВЕРКА НОД и ПЕРЕЗАПУСК
# --------------------------------------------------------------------------
if [ "$H3_SELFTEST" = "1" ]; then
    echo "🧪 Самопроверка: загружаю ноды отдельным процессом (без запуска сервера, на CPU)..."
    ( cd "$COMFY_DIR" && timeout 600 $PY_EXEC main.py --cpu --quick-test-for-ci ) > /workspace/h3_selftest.log 2>&1
    SELFTEST_RC=$?
    BAD=$(grep -E "IMPORT FAILED|Cannot import" /workspace/h3_selftest.log | sort -u)
    if [ -n "$BAD" ]; then
        echo "⚠️ При загрузке нод есть ошибки импорта (полный лог: /workspace/h3_selftest.log):" >&2
        echo "$BAD" | sed 's/^/   /' >&2
    elif [ "$SELFTEST_RC" -ne 0 ]; then
        echo "⚠️ Самопроверка завершилась с кодом $SELFTEST_RC — смотри /workspace/h3_selftest.log" >&2
    else
        echo "✅ Все ноды загрузились без ошибок импорта."
    fi
fi

# На первом запуске ComfyUI ждёт /.provisioning и стартует сам — перезапуск не нужен.
if [ -f /.provisioning ]; then
    echo "ℹ️ ComfyUI стартует автоматически после завершения provisioning."
elif command -v supervisorctl >/dev/null 2>&1 && supervisorctl status comfyui 2>/dev/null | grep -q RUNNING; then
    echo "🔁 Перезапускаю ComfyUI, чтобы подхватил ноды и модели..."
    supervisorctl restart comfyui >/dev/null 2>&1 || echo "   ⚠️ не удалось перезапустить — перезапусти вручную" >&2
fi

# --------------------------------------------------------------------------
# ИТОГ
# --------------------------------------------------------------------------
echo ""
echo "📦 Модели: $OK_MODELS из $TOTAL_MODELS скачано"
if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    echo "⚠️ Не скачались:"
    for f in "${FAILED_MODELS[@]}"; do echo "   - $f"; done
    printf '%s\n' "${FAILED_MODELS[@]}" > /workspace/h3_failed_models.txt
fi
if [ ${#FAILED_NODES[@]} -gt 0 ]; then
    echo "⚠️ Не поставились ноды:"
    for n in "${FAILED_NODES[@]}"; do echo "   - $n"; done
fi
echo ""
echo "ℹ️ Советы по запуску (профиль $H3_PROFILE):"
if [ "$H3_PROFILE" = "5090" ]; then
    echo "   • На 896×1344 / 8 с включи Chunking в панели Settings; если в логе 'partially loaded' — снизь разрешение или возьми карту 80+ ГБ."
    echo "   • Если семплер вдруг в разы медленнее обычного — переключи Visual VAE с int8_convrot на fp16 (известный случай на Windows)."
else
    echo "   • Текстовый энкодер int8_convrot (если скачан) выбери в панели Settings вручную: в воркфлоу по умолчанию стоит nvfp4_awq."
    echo "   • bf16-модель (если скачана) выбери в слоте UNET FL2VA и сравни с int8: ожидай заметно больше времени на ролик."
fi
echo "   • Если ComfyUI падает по ОЗУ: добавь --disable-pinned-memory в COMFYUI_ARGS шаблона."
echo "   • Turbo (DaSiWa): euler/simple, 4–8 шагов, shift video 6–12 / audio 3–5 — для черновиков (начни с 8 шагов)."
echo "   • Обычная (DaSiWa): res_multistep/simple или euler/simple, 20–25 шагов, shift video 10–12 / audio 3–5 — для финала. Выбери её в обоих слотах UNET."
echo "   • Звук: у Turbo бывают просадки голоса и другая громкость — сравни Turbo (8 шагов) и обычную на реплике: то же изображение, промпт, фиксированное зерно."
echo "   • Пик VRAM смотри в nvidia-smi и в логе ComfyUI (строки 'loaded completely' / 'partially loaded')."
echo "⏱️ Всего времени: $(( (SECONDS-START_TS)/60 )) мин"
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
