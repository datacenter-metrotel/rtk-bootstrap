#!/usr/bin/env bash
#
# install-rtk.sh — Instalador completo de rtk (Rust Token Killer) para Ubuntu 24.04
#
# Repositorio oficial: https://github.com/rtk-ai/rtk
#
# Estrategia de instalación (en orden):
#   1) Si rtk YA está instalado y es el correcto -> no reinstala.
#   2) Instalador oficial (install.sh)  [no requiere Rust]
#   3) Fallback: cargo install --git <repo>  [instala Rust con sudo si falta]
#
# Además:
#   - Avisa de TODAS las dependencias previas antes de tocar el sistema.
#   - Configura npm en $HOME (evita EACCES sin sudo) e instala ccusage.
#   - Integra el hook de Claude Code (rtk init).
#   - Deja rtk PROBADO con un test real al final (distingue el RTK correcto del
#     impostor "Rust Type Kit" usando 'rtk gain').
#
# Uso:
#   ./install-rtk.sh                 # instalación + integración + test
#   ./install-rtk.sh --check         # solo diagnóstico / lista de dependencias
#   ./install-rtk.sh --yes           # no pregunta confirmaciones (modo desatendido)
#   ./install-rtk.sh --method cargo  # fuerza método: auto|script|cargo
#   ./install-rtk.sh --no-ccusage    # omite ccusage (cc-economics es opcional)
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
RTK_REPO="https://github.com/rtk-ai/rtk"
RTK_INSTALL_SH="https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"

# ---------------------------------------------------------------------------
# Estética
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
info() { printf '%s[info]%s %s\n' "$BLUE"   "$RESET" "$*"; }
ok()   { printf '%s[ok]%s %s\n'   "$GREEN"  "$RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()  { printf '%s[err]%s %s\n'  "$RED"    "$RESET" "$*" >&2; }
hr()   { printf '%s%s%s\n' "$BOLD" "============================================================" "$RESET"; }
step() { hr; printf '%s%s%s\n' "$BOLD" "$*" "$RESET"; hr; }

declare -A STATUS
set_status() { STATUS["$1"]="$2"; }

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
CHECK_ONLY=0
ASSUME_YES=0
METHOD="auto"      # auto | script | cargo
SKIP_CCUSAGE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)      CHECK_ONLY=1; shift ;;
    --yes|-y)     ASSUME_YES=1; shift ;;
    --method)     METHOD="${2:-auto}"; shift 2 ;;
    --no-ccusage) SKIP_CCUSAGE=1; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -28; exit 0 ;;
    *) err "Argumento desconocido: $1"; exit 1 ;;
  esac
done

confirm() {
  # confirm "pregunta" -> 0 si sí
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[yYsS]$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

# Detecta si el rtk presente es el CORRECTO (Token Killer) y no el impostor.
# Criterio oficial: 'rtk gain' funciona en el Token Killer; falla en el Type Kit.
rtk_is_correct() {
  have rtk || return 1
  rtk gain >/dev/null 2>&1
}

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then SUDO="sudo"; fi
# Etiqueta legible para los mensajes (evita comillas vacías al correr como root)
if [[ -n "$SUDO" ]]; then SUDO_LABEL="sudo"; else SUDO_LABEL="(ya sos root)"; fi

# ===========================================================================
# 0. AVISO DE DEPENDENCIAS PREVIAS
# ===========================================================================
step "0/8  Dependencias previas (revisión)"

cat <<EOF
Este instalador puede necesitar lo siguiente. Te aviso ANTES de tocar nada:

  Imprescindibles (se intentan instalar/usar):
    - curl            : para el instalador oficial de rtk
    - git             : para el fallback vía cargo
    - Node.js 20+ + npm : para 'ccusage' (reporte cc-economics, opcional)

  Solo si hay que compilar rtk con cargo (fallback):
    - Rust toolchain (rustc + cargo)  -> se instala vía rustup
    - build-essential (gcc, make...)  -> se instala con: ${SUDO_LABEL} apt-get install
    - pkg-config, libssl-dev          -> dependencias de compilación

  Privilegios:
    - Se usará '${SUDO_LABEL}' SOLO para instalar paquetes de sistema (apt) si faltan.
    - La instalación de rtk en sí NO requiere root (va a tu \$HOME/.cargo o \$HOME/.local).

  Repositorio oficial (IMPORTANTE):
    - $RTK_REPO
    - Nunca se usa 'cargo install rtk' pelado: en crates.io existe un paquete
      homónimo equivocado ("Rust Type Kit"). Siempre se usa la URL del repo.
EOF
echo

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  info "Modo --check: solo diagnóstico, no se instala ni modifica nada."
else
  if ! confirm "¿Continuar con la instalación e integración?"; then
    warn "Cancelado por el usuario."; exit 0
  fi
fi

# ===========================================================================
# 1. ¿rtk ya instalado y correcto?
# ===========================================================================
step "1/8  Estado actual de rtk"

if rtk_is_correct; then
  ok "rtk ya está instalado y es el correcto: $(rtk --version 2>/dev/null)"
  ok "Ruta: $(command -v rtk)"
  set_status "instalacion" "PASS"
  RTK_ALREADY=1
elif have rtk; then
  warn "Hay un 'rtk' en PATH pero 'rtk gain' falla."
  warn "Probablemente sea el paquete equivocado ('Rust Type Kit'), no el Token Killer."
  warn "Se procederá a instalar el correcto desde $RTK_REPO."
  set_status "instalacion" "PENDING"
  RTK_ALREADY=0
else
  info "rtk no está instalado. Se instalará desde el repo oficial."
  set_status "instalacion" "PENDING"
  RTK_ALREADY=0
fi

# ===========================================================================
# 2. Dependencias base de sistema (curl/git)
# ===========================================================================
step "2/8  Dependencias base (curl, git)"

ensure_apt_pkg() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    ok "$pkg ya instalado."
    return 0
  fi
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    info "(check) Faltaría instalar: $pkg"
    return 0
  fi
  info "Instalando $pkg vía apt..."
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq "$pkg"
}

if [[ "$RTK_ALREADY" -eq 0 ]]; then
  for p in curl git; do ensure_apt_pkg "$p"; done
fi
set_status "deps_base" "PASS"

# ===========================================================================
# 3. Instalar rtk: binario/script oficial -> fallback cargo
# ===========================================================================
step "3/8  Instalación de rtk"

install_via_script() {
  have curl || { err "curl no disponible."; return 1; }
  info "Probando instalador oficial (install.sh)..."
  curl -fsSL "$RTK_INSTALL_SH" | sh
}

install_rust() {
  if have cargo; then
    ok "Rust/cargo ya presente: $(cargo --version)"
    return 0
  fi
  warn "Rust no está instalado y se necesita para el fallback cargo."
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    info "(check) Se instalaría: build-essential pkg-config libssl-dev + rustup"
    return 0
  fi
  if ! confirm "¿Instalar Rust (rustup) y las dependencias de compilación (apt, requiere $SUDO)?"; then
    err "Sin Rust no se puede compilar rtk. Abortando el fallback."
    return 1
  fi
  for p in build-essential pkg-config libssl-dev; do ensure_apt_pkg "$p"; done
  info "Instalando rustup (toolchain stable)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
  have cargo
}

install_via_cargo() {
  install_rust || return 1
  info "Compilando e instalando rtk desde $RTK_REPO (puede tardar ~1-2 min)..."
  cargo install --git "$RTK_REPO" --force
  # asegurar PATH de cargo
  export PATH="$HOME/.cargo/bin:$PATH"
}

if [[ "$RTK_ALREADY" -eq 1 ]]; then
  info "rtk ya instalado y correcto: se omite la instalación."
  set_status "instalacion" "PASS"
elif [[ "$CHECK_ONLY" -eq 1 ]]; then
  info "(check) Método elegido: $METHOD (auto = script y luego cargo)"
  set_status "instalacion" "SKIP"
else
  INSTALLED=0
  case "$METHOD" in
    script)
      install_via_script && INSTALLED=1 ;;
    cargo)
      install_via_cargo && INSTALLED=1 ;;
    auto|*)
      if install_via_script; then
        INSTALLED=1
      else
        warn "Instalador oficial no disponible o falló. Pasando a cargo..."
        install_via_cargo && INSTALLED=1
      fi ;;
  esac

  # Reevaluar PATH típico de rtk
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

  if [[ "$INSTALLED" -eq 1 ]] && have rtk; then
    ok "rtk instalado: $(rtk --version 2>/dev/null) en $(command -v rtk)"
    set_status "instalacion" "PASS"
  else
    err "No se pudo instalar rtk por ningún método."
    set_status "instalacion" "FAIL"
  fi
fi

# ===========================================================================
# 4. PATH de rtk en ~/.bashrc (cargo/local)
# ===========================================================================
step "4/8  PATH de rtk en ~/.bashrc"

BASHRC="$HOME/.bashrc"
ensure_path_line() {
  local line="$1" tag="$2"
  if grep -qsF "$line" "$BASHRC"; then
    ok "Ya presente en .bashrc: $tag"
  elif [[ "$CHECK_ONLY" -eq 1 ]]; then
    info "(check) Se añadiría a .bashrc: $tag"
  else
    { echo ''; echo "# rtk-installer: $tag"; echo "$line"; } >> "$BASHRC"
    ok "Añadido a .bashrc: $tag"
  fi
}
ensure_path_line 'export PATH="$HOME/.cargo/bin:$PATH"'  'cargo bin'
ensure_path_line 'export PATH="$HOME/.local/bin:$PATH"'  'local bin'
set_status "path_rtk" "PASS"

# ===========================================================================
# 5. npm en $HOME + ccusage (opcional)
# ===========================================================================
step "5/8  npm en \$HOME y ccusage (cc-economics, opcional)"

if [[ "$SKIP_CCUSAGE" -eq 1 ]]; then
  info "Omitido por --no-ccusage."
  set_status "ccusage" "SKIP"
elif ! have npm; then
  warn "npm no está instalado. ccusage (cc-economics) quedará no disponible."
  warn "Instalá Node 20+ (nvm o nodesource) si querés el reporte económico."
  set_status "ccusage" "SKIP"
elif [[ "$CHECK_ONLY" -eq 1 ]]; then
  info "(check) Se configuraría npm prefix en \$HOME y se instalaría ccusage."
  set_status "ccusage" "SKIP"
else
  NPM_GLOBAL="$HOME/.npm-global"
  if [[ "$(npm config get prefix 2>/dev/null)" != "$NPM_GLOBAL" ]]; then
    mkdir -p "$NPM_GLOBAL"; npm config set prefix "$NPM_GLOBAL"
    ok "npm prefix -> $NPM_GLOBAL (evita EACCES sin sudo)"
  else
    ok "npm prefix ya configurado en $NPM_GLOBAL"
  fi
  ensure_path_line 'export PATH="$HOME/.npm-global/bin:$PATH"' 'npm global bin'
  export PATH="$HOME/.npm-global/bin:$PATH"

  info "Instalando ccusage..."
  if npm install -g ccusage >/dev/null 2>&1 && have ccusage; then
    ok "ccusage instalado: $(ccusage --version 2>/dev/null || echo '??')"
    if ccusage monthly --json 2>/dev/null | grep -q '"month"'; then
      ok "JSON de ccusage compatible con rtk."
      set_status "ccusage" "PASS"
    else
      warn "ccusage instalado pero su JSON no trae 'month' como espera rtk."
      warn "cc-economics puede fallar (es opcional, no afecta el filtrado)."
      set_status "ccusage" "WARN"
    fi
  else
    warn "No se pudo instalar ccusage. cc-economics no estará disponible."
    set_status "ccusage" "WARN"
  fi
fi

# ===========================================================================
# 6. Integración con Claude Code (hook)
# ===========================================================================
step "6/8  Integración con Claude Code (rtk init)"

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  info "(check) Se correría 'rtk init' para registrar el hook PreToolUse."
  set_status "hook_init" "SKIP"
elif ! have rtk; then
  err "rtk no disponible: no se puede integrar el hook."
  set_status "hook_init" "FAIL"
else
  if rtk init >/dev/null 2>&1; then
    ok "rtk init ejecutado (hook + instrucciones en CLAUDE.md)."
  else
    warn "rtk init devolvió error (¿ya inicializado / fuera de proyecto?)."
  fi
  VERIFY_OUT="$(rtk verify 2>&1)"
  echo "$VERIFY_OUT"
  if echo "$VERIFY_OUT" | grep -qiE 'PASS|registered|tests passed'; then
    ok "Hook verificado (rtk verify)."
    set_status "hook_init" "PASS"
  else
    warn "rtk verify no reportó PASS. Revisá settings.json."
    set_status "hook_init" "WARN"
  fi
fi

# ===========================================================================
# 7. TEST FINAL — rtk instalado y 100% funcional
# ===========================================================================
step "7/8  TEST de funcionamiento"

TEST_PASS=0
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  info "(check) Se ejecutaría la batería de tests."
  set_status "test" "SKIP"
elif ! have rtk; then
  err "rtk no disponible: test no ejecutado."
  set_status "test" "FAIL"
else
  PASS=0; TOTAL=0

  run_test() {
    local desc="$1"; shift
    TOTAL=$((TOTAL+1))
    if "$@" >/dev/null 2>&1; then
      ok "TEST $TOTAL: $desc"
      PASS=$((PASS+1))
    else
      err "TEST $TOTAL: $desc  -> FALLÓ"
    fi
  }

  # T1: rtk responde a --version
  run_test "rtk --version responde" rtk --version
  # T2: es el RTK CORRECTO (gain funciona, no es el impostor Type Kit)
  run_test "es el Token Killer correcto (rtk gain OK)" rtk gain
  # T3: filtra salida de un comando real (ls comprimido)
  run_test "rtk ls produce salida" bash -c 'rtk ls >/dev/null'
  # T4: el filtro realmente comprime vs nativo (heurística: salida no vacía y <= nativa)
  run_test "rtk comprime salida de ls" bash -c '
      native=$(ls -la / | wc -c)
      filtered=$(rtk ls -la / 2>/dev/null | wc -c)
      [ "$filtered" -gt 0 ] && [ "$filtered" -le "$native" ]'
  # T5: hook verificado
  run_test "rtk verify reporta integridad" bash -c 'rtk verify 2>&1 | grep -qiE "PASS|registered|tests passed"'

  echo
  if [[ "$PASS" -eq "$TOTAL" ]]; then
    ok "TODOS los tests pasaron ($PASS/$TOTAL)."
    set_status "test" "PASS"
    TEST_PASS=1
  elif [[ "$PASS" -ge 3 ]]; then
    warn "Tests parciales ($PASS/$TOTAL). rtk funciona pero revisá los fallidos."
    set_status "test" "WARN"
  else
    err "Tests insuficientes ($PASS/$TOTAL). rtk NO quedó funcional."
    set_status "test" "FAIL"
  fi
fi

# ===========================================================================
# 8. VEREDICTO FINAL
# ===========================================================================
step "8/8  VALIDACIÓN FINAL"

print_row() {
  local name="$1" st="${STATUS[$1]:-?}" color="$RESET"
  case "$st" in PASS) color="$GREEN";; WARN) color="$YELLOW";; FAIL) color="$RED";; SKIP|PENDING) color="$BLUE";; esac
  printf '  %-16s %s%s%s\n' "$name" "$color" "$st" "$RESET"
}

echo "Resumen:"
for k in instalacion deps_base path_rtk ccusage hook_init test; do
  [[ -n "${STATUS[$k]:-}" ]] && print_row "$k"
done
echo

FAILS=0; WARNS=0
for k in "${!STATUS[@]}"; do
  [[ "${STATUS[$k]}" == "FAIL" ]] && FAILS=$((FAILS+1))
  [[ "${STATUS[$k]}" == "WARN" ]] && WARNS=$((WARNS+1))
done

hr
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  info "VEREDICTO (check): diagnóstico completado, sin cambios aplicados."
  RC=0
elif [[ "$FAILS" -gt 0 ]]; then
  err "VEREDICTO: instalación INCOMPLETA — $FAILS componente(s) en FAIL."
  RC=1
elif [[ "${STATUS[test]:-}" == "PASS" ]]; then
  ok "VEREDICTO: rtk INSTALADO, INTEGRADO Y 100% FUNCIONAL (test superado)."
  [[ "$WARNS" -gt 0 ]] && warn "Con $WARNS advertencia(s) menor(es) opcionales."
  RC=0
else
  warn "VEREDICTO: rtk instalado pero el test no fue 100%. Revisá arriba."
  RC=0
fi
hr

echo
info "Recargá tu shell para tomar los PATH nuevos:"
echo "    source ~/.bashrc"
echo
info "El hook hará el ahorro automático en Claude Code (reabrí tu sesión)."
exit "$RC"
