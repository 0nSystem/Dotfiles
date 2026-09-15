#!/usr/bin/env bash
# Instala/actualiza las herramientas de desarrollo base en este equipo (Manjaro/Arch):
# github-cli, oh-my-zsh (con sus plugins), yay (AUR helper), Visual Studio Code (AUR),
# Rust (vía rustup, tal cual lo indica rust-lang.org, sin pasar por asdf), asdf (gestor
# de versiones, con los plugins nodejs/java), zellij (multiplexor de terminal) y
# mission-center (monitor gráfico de CPU/GPU/memoria/consumo). Siempre de forma
# idempotente y sin dejar residuos a medias si algo falla a mitad de camino.
#
# Por defecto solo se ven las líneas de progreso (==>, check/cruz); la salida ruidosa
# de pacman/makepkg/git/curl/oh-my-zsh se manda a un log y no ensucia la terminal.
# Uso:
#   ./setup-dev-tools.sh            # salida limpia, todo va al log
#   ./setup-dev-tools.sh -v         # además de al log, muestra la salida completa en vivo
#   VERBOSE=1 ./setup-dev-tools.sh  # equivalente a -v
# El log siempre se conserva (aunque no uses -v) y su ruta se imprime al terminar,
# o al fallar, para poder revisarlo después.
#
# IMPORTANTE: ejecutar como usuario normal, NO con sudo. makepkg (usado para compilar yay)
# se niega a correr como root; el script pide sudo por su cuenta solo para lo que
# realmente necesita privilegios (pacman).
set -euo pipefail

VERBOSE="${VERBOSE:-0}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        *)
            echo "Uso: $0 [-v|--verbose]" >&2
            exit 1
            ;;
    esac
done

if [[ -t 1 ]]; then
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
    C_GREEN=''; C_RED=''; C_RESET=''
fi

# ok <mensaje>    -> check verde (ya estaba instalado/configurado, no se toca)
# missing <mensaje> -> cruz roja (falta, se va a instalar/configurar ahora)
ok()      { echo "    ${C_GREEN}✔${C_RESET} $*"; }
missing() { echo "    ${C_RED}✘${C_RESET} $*"; }

LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/setup-dev-tools.XXXXXX.log")"

# run_logged <comando...> -> ejecuta el comando ruidoso mandando su salida al log;
# con -v/VERBOSE=1 además la muestra en pantalla en vivo (vía tee).
run_logged() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        "$@" 2>&1 | tee -a "$LOG_FILE"
    else
        "$@" >>"$LOG_FILE" 2>&1
    fi
}

if [[ $EUID -eq 0 ]]; then
    echo "No ejecutes este script como root ni con sudo." >&2
    echo "Ejecútalo como tu usuario normal: ./setup-dev-tools.sh" >&2
    exit 1
fi

# Cachea las credenciales de sudo una vez al principio y las mantiene vivas mientras
# dura el script, para no interrumpir la compilación de yay pidiendo la contraseña otra vez.
sudo -v
( while true; do sudo -n true; sleep 60; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

YAY_BUILD_DIR=""
ASDF_TMP_DIR=""

cleanup() {
    local ret=$?
    [[ -n "$YAY_BUILD_DIR" && -d "$YAY_BUILD_DIR" ]] && rm -rf "$YAY_BUILD_DIR"
    [[ -n "$ASDF_TMP_DIR" && -d "$ASDF_TMP_DIR" ]] && rm -rf "$ASDF_TMP_DIR"
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    if [[ $ret -ne 0 ]]; then
        echo >&2
        echo "==> Algo falló (código $ret). Log completo en: $LOG_FILE" >&2
        if [[ "$VERBOSE" -ne 1 ]]; then
            echo "    Últimas líneas del log:" >&2
            tail -n 20 "$LOG_FILE" >&2
        fi
    fi
}
trap cleanup EXIT

echo "==> [1/8] Paquetes base (base-devel, git, fakeroot, zsh), GitHub CLI, zellij, pygments y mission-center"
PACMAN_PACKAGES=(base-devel git fakeroot zsh github-cli zellij python-pygments mission-center)
for pkg in "${PACMAN_PACKAGES[@]}"; do
    if [[ "$pkg" == base-devel ]]; then
        # base-devel es un grupo, no un paquete: se considera instalado si ya hay
        # algún paquete del grupo presente.
        if [[ -n "$(pacman -Qg base-devel 2>/dev/null)" ]]; then ok "$pkg"; else missing "$pkg"; fi
    elif pacman -Qi "$pkg" &>/dev/null; then
        ok "$pkg"
    else
        missing "$pkg"
    fi
done
run_logged sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

echo "==> [2/8] oh-my-zsh"
ZSHRC="$HOME/.zshrc"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "oh-my-zsh"
else
    missing "oh-my-zsh"
    echo "    Instalando oh-my-zsh (modo desatendido, sin cambiar el shell por defecto;"
    echo "    detalle en el log). El instalador hace su comportamiento estándar: se queda"
    echo "    con una copia de tu .zshrc anterior (.zshrc.pre-oh-my-zsh) y escribe el suyo."
    export RUNZSH=no CHSH=no
    run_logged sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    unset RUNZSH CHSH
fi

echo "==> [3/8] yay (AUR helper)"
if command -v yay >/dev/null 2>&1; then
    ok "yay ($(yay --version | head -n1))"
else
    missing "yay"
    YAY_BUILD_DIR="$(mktemp -d)"
    echo "    Clonando y compilando yay en $YAY_BUILD_DIR (detalle en el log)"
    run_logged git clone --depth=1 https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR"
    (cd "$YAY_BUILD_DIR" && run_logged makepkg -si --noconfirm)
    rm -rf "$YAY_BUILD_DIR"
    YAY_BUILD_DIR=""
    echo "    yay instalado: $(yay --version | head -n1)"
fi

echo "==> [4/8] Visual Studio Code (AUR: visual-studio-code-bin)"
if pacman -Qi visual-studio-code-bin &>/dev/null; then
    ok "visual-studio-code-bin"
else
    missing "visual-studio-code-bin"
fi
run_logged yay -S --needed --noconfirm visual-studio-code-bin

echo "==> [5/8] Rust (rustup, instalador oficial de rust-lang.org, sin pasar por asdf)"
if [[ -x "$HOME/.cargo/bin/rustc" ]]; then
    ok "rust ($("$HOME/.cargo/bin/rustc" --version))"
else
    missing "rust"
    echo "    Instalando con rustup (detalle en el log). --no-modify-path porque el PATH"
    echo "    de ~/.cargo/bin lo añadimos nosotros abajo, de forma idempotente."
    run_logged sh -c \
        "$(curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs)" -- -y --no-modify-path
    echo "    rust instalado: $("$HOME/.cargo/bin/rustc" --version)"
fi

CARGO_PATH_LINE='export PATH="$HOME/.cargo/bin:$PATH"'
if [[ -f "$ZSHRC" ]] && grep -qF "$CARGO_PATH_LINE" "$ZSHRC"; then
    ok "PATH de rust (~/.cargo/bin) en $ZSHRC"
else
    missing "PATH de rust (~/.cargo/bin) en $ZSHRC (se añade)"
    { echo ''; echo '# Añadido por setup-dev-tools.sh: binarios de rust/cargo (rustup)'; echo "$CARGO_PATH_LINE"; } >> "$ZSHRC"
fi

echo "==> [6/8] asdf (binario oficial desde GitHub Releases, sin el clon git antiguo)"
ASDF_BIN_DIR="$HOME/.local/bin"
ASDF_CMD="$ASDF_BIN_DIR/asdf"
mkdir -p "$ASDF_BIN_DIR"

case "$(uname -m)" in
    x86_64) ASDF_ARCH=amd64 ;;
    aarch64|arm64) ASDF_ARCH=arm64 ;;
    armv7l) ASDF_ARCH=arm ;;
    *)
        echo "    Arquitectura $(uname -m) no soportada por este script." >&2
        exit 1
        ;;
esac

ASDF_LATEST_TAG="$(curl -fsSL https://api.github.com/repos/asdf-vm/asdf/releases/latest \
    | grep -oP '"tag_name":\s*"\K[^"]+')"

if [[ -z "$ASDF_LATEST_TAG" ]]; then
    echo "    No se pudo averiguar la última versión de asdf en GitHub." >&2
    exit 1
fi

CURRENT_ASDF_VERSION=""
if command -v asdf >/dev/null 2>&1; then
    CURRENT_ASDF_VERSION="$(asdf version 2>/dev/null | head -n1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)"
fi

if [[ "$CURRENT_ASDF_VERSION" == "$ASDF_LATEST_TAG" ]]; then
    ok "asdf ($ASDF_LATEST_TAG)"
else
    missing "asdf (${CURRENT_ASDF_VERSION:-no instalado} -> $ASDF_LATEST_TAG)"
    if [[ -d "$HOME/.asdf/.git" ]]; then
        echo "    Aviso: detectada una instalación antigua de asdf (clon git) en ~/.asdf."
        echo "           Se deja intacta (ahí puede haber plugins/versiones instaladas);"
        echo "           solo se instala el binario nuevo en $ASDF_BIN_DIR."
    fi

    ASDF_TARBALL="asdf-${ASDF_LATEST_TAG}-linux-${ASDF_ARCH}.tar.gz"
    ASDF_URL="https://github.com/asdf-vm/asdf/releases/download/${ASDF_LATEST_TAG}/${ASDF_TARBALL}"
    ASDF_TMP_DIR="$(mktemp -d)"

    echo "    Descargando $ASDF_URL (detalle en el log)"
    run_logged curl -fsSL "$ASDF_URL" -o "$ASDF_TMP_DIR/$ASDF_TARBALL"
    run_logged tar -xzf "$ASDF_TMP_DIR/$ASDF_TARBALL" -C "$ASDF_TMP_DIR"
    install -m 755 "$ASDF_TMP_DIR/asdf" "$ASDF_BIN_DIR/asdf"
    rm -rf "$ASDF_TMP_DIR"
    ASDF_TMP_DIR=""
    echo "    asdf instalado: $("$ASDF_CMD" version)"
fi

# El binario de asdf va en ~/.local/bin y los shims (node, java, npm, javac...) que
# genera para cada versión instalada van en ~/.asdf/shims: ambas rutas hacen falta en
# el PATH para poder usar asdf y lo que instale con él.
ASDF_PATH_LINE='export PATH="$HOME/.asdf/shims:$HOME/.local/bin:$PATH"'
if [[ -f "$ZSHRC" ]] && grep -qF "$ASDF_PATH_LINE" "$ZSHRC"; then
    ok "PATH de asdf (shims + $ASDF_BIN_DIR) en $ZSHRC"
else
    missing "PATH de asdf (shims + $ASDF_BIN_DIR) en $ZSHRC (se añade)"
    { echo ''; echo '# Añadido por setup-dev-tools.sh: binarios y shims de asdf'; echo "$ASDF_PATH_LINE"; } >> "$ZSHRC"
fi

echo "==> [7/8] Plugins de asdf: nodejs, java"
add_asdf_plugin() {
    # add_asdf_plugin <nombre>
    local name=$1
    if "$ASDF_CMD" plugin list 2>/dev/null | grep -qx "$name"; then
        ok "asdf plugin $name"
    else
        missing "asdf plugin $name"
        run_logged "$ASDF_CMD" plugin add "$name"
    fi
}
add_asdf_plugin nodejs
add_asdf_plugin java

# El plugin de java de asdf necesita esta línea en el shell para que JAVA_HOME se
# actualice solo al cambiar de versión con `asdf` (ver README de asdf-community/asdf-java).
# Se deja protegida con el [ -f ... ] por si el plugin no llegó a instalarse.
JAVA_HOME_LINE='[ -f "$HOME/.asdf/plugins/java/set-java-home.zsh" ] && . "$HOME/.asdf/plugins/java/set-java-home.zsh"'
if grep -qF "$JAVA_HOME_LINE" "$ZSHRC" 2>/dev/null; then
    ok "JAVA_HOME automático (plugin java de asdf) en $ZSHRC"
else
    missing "JAVA_HOME automático (plugin java de asdf) en $ZSHRC (se añade)"
    { echo ''; echo '# Añadido por setup-dev-tools.sh: JAVA_HOME automático del plugin java de asdf'; echo "$JAVA_HOME_LINE"; } >> "$ZSHRC"
fi

echo "==> [8/8] Plugins de oh-my-zsh: asdf, extract, colorize, colored-man-pages (built-in) + zsh-autosuggestions, zsh-syntax-highlighting (externos)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_or_update_omz_plugin() {
    # clone_or_update_omz_plugin <nombre> <url> <destino>
    local name=$1 url=$2 dest=$3
    if [[ -d "$dest/.git" ]]; then
        ok "$name"
        run_logged git -C "$dest" pull --ff-only
    else
        missing "$name"
        run_logged git clone --depth=1 "$url" "$dest"
    fi
}

for pkg in asdf extract colorize colored-man-pages; do
    ok "$pkg (incluido en oh-my-zsh)"
done
clone_or_update_omz_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_or_update_omz_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# zsh-syntax-highlighting debe ser el último de la lista (necesita envolver los widgets
# que registren el resto de plugins).
OMZ_PLUGINS_LINE='plugins=(asdf extract colorize colored-man-pages zsh-autosuggestions zsh-syntax-highlighting)'
if grep -qF "$OMZ_PLUGINS_LINE" "$ZSHRC" 2>/dev/null; then
    ok "línea plugins=(...) en $ZSHRC"
elif grep -qE '^plugins=\(' "$ZSHRC" 2>/dev/null; then
    missing "línea plugins=(...) en $ZSHRC (se actualiza)"
    sed -i "s/^plugins=(.*)\$/$OMZ_PLUGINS_LINE/" "$ZSHRC"
else
    missing "línea plugins=(...) en $ZSHRC (se añade)"
    printf '\n%s\n' "$OMZ_PLUGINS_LINE" >> "$ZSHRC"
fi

echo
echo "==> Listo. gh, yay, code (VS Code), rust (rustup), asdf (+ plugins nodejs/java),"
echo "    zellij, mission-center y oh-my-zsh (plugins asdf/extract/colorize/"
echo "    colored-man-pages/zsh-autosuggestions/zsh-syntax-highlighting) disponibles."
echo "    Instala una versión de node/java con, por ejemplo:"
echo "      asdf install nodejs latest && asdf set -u nodejs latest"
echo "      asdf install java latest:temurin-21 && asdf set -u java latest:temurin-21"
echo "    Y actualiza rust cuando quieras con: rustup update"
echo "    Reinicia la terminal si es la primera vez que se ha tocado el PATH o el .zshrc."
echo "    Log completo de esta ejecución: $LOG_FILE"
