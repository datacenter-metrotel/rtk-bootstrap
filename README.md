# install-rtk

Instalador completo de **rtk (Rust Token Killer)** para distribuciones
**Debian-based**. Probado en **Ubuntu 24.04**, **Debian 13** y **Kali Linux**.

Instala rtk de verdad, lo integra con **Claude Code y Gemini CLI** y lo deja
**probado con un test** antes de darte el visto bueno. Un solo comando.

Repositorio oficial de rtk: <https://github.com/rtk-ai/rtk>

## Qué hace

1. **Avisa de las dependencias previas** antes de tocar nada.
2. **Detecta si rtk ya está instalado** y si es el correcto (ver nota sobre el
   impostor más abajo). Si ya está bien, no reinstala.
3. **Instala rtk** con esta estrategia en cascada:
   - Primero el **instalador oficial** (`install.sh`), que no requiere Rust.
   - Si falla, **fallback a `cargo install --git`**, instalando el toolchain de
     **Rust (rustup)** y las dependencias de compilación vía `apt` (pide `sudo`
     solo para eso).
4. **Configura los PATH** (`~/.cargo/bin`, `~/.local/bin`, `~/.npm-global/bin`) en
   `~/.bashrc`, de forma idempotente.
5. **Instala `ccusage`** para `rtk cc-economics` (opcional), arreglando el prefijo
   de npm en `$HOME` para evitar el error `EACCES` sin usar `sudo`.
6. **Integra los hooks de los agentes** — por defecto **Claude Code** (`rtk init`)
   **y Gemini CLI** (`rtk init -g --gemini`); configurable con `--target`. Verifica
   con `rtk verify`.
7. **Ejecuta una batería de tests** que confirma que rtk funciona de verdad.
8. Imprime un **resumen y un veredicto final**.

## La batería de tests

El paso 7 corre 5 pruebas reales:

1. `rtk --version` responde.
2. **Es el RTK correcto**: `rtk gain` funciona (criterio oficial para distinguirlo
   del paquete homónimo "Rust Type Kit").
3. `rtk ls` produce salida.
4. `rtk` realmente **comprime** la salida de `ls` respecto al comando nativo.
5. `rtk verify` reporta integridad del hook.

Solo si pasan todas, el veredicto es **"100% FUNCIONAL"**.

## ⚠️ Nota importante: el name collision

En crates.io existe un paquete llamado igual, **"Rust Type Kit"**, que NO es el
Token Killer. Por eso el instalador **nunca** usa `cargo install rtk` pelado:
siempre instala desde la URL del repo oficial. Y distingue el paquete correcto
porque en el Token Killer el comando `rtk gain` funciona, mientras que en el
impostor falla.

## Requisitos previos

- Ubuntu 24.04, Debian 13 o Kali Linux (probado en las tres; debería funcionar en
  otras distros Debian-based con `apt`).
- Acceso a internet.
- `sudo` disponible **solo si** hay que instalar paquetes de sistema (Rust,
  build-essential) para el fallback de compilación. Si el instalador oficial
  funciona, no se necesita `sudo` en absoluto.
- Node.js 20+ y npm **solo si** querés `cc-economics` (opcional).

## Uso

```bash
chmod +x install-rtk.sh

./install-rtk.sh                  # instala + integra Claude Code y Gemini CLI + test
./install-rtk.sh --target claude  # integra solo Claude Code
./install-rtk.sh --target gemini  # integra solo Gemini CLI
./install-rtk.sh --check          # solo diagnóstico y lista de dependencias
./install-rtk.sh --yes            # desatendido (no pregunta confirmaciones)
./install-rtk.sh --method cargo    # fuerza el método (auto|script|cargo)
./install-rtk.sh --no-ccusage     # omite ccusage
```

Al terminar, recargá la shell:

```bash
source ~/.bashrc
```

## Interpretar el veredicto

- **`INSTALADO, INTEGRADO Y 100% FUNCIONAL`** — los 5 tests pasaron. rtk anda y el
  hook hará el ahorro automático en Claude Code.
- **`instalado pero el test no fue 100%`** — rtk funciona pero alguna prueba
  secundaria falló; revisá los mensajes.
- **`instalación INCOMPLETA`** — hubo un FAIL crítico (no se pudo instalar, etc.).

## Notas

- **Agentes soportados.** Por defecto integra Claude Code (`rtk init`) y Gemini CLI
  (`rtk init -g --gemini`). El hook de cada uno se instala aunque el agente no esté
  presente todavía; empezará a funcionar cuando lo instales y lo reinicies. rtk NO
  soporta Claude Desktop de forma nativa (eso requiere un puente MCP aparte).
- **`cc-economics` es opcional.** Si falla por una versión de `ccusage` cuyo JSON
  cambió de formato (`missing field 'month'`), **no afecta** el filtrado ni el hook.
- **El hook es lo que importa**: con `rtk verify` en `PASS`, el ahorro en Claude
  Code es automático, sin instrucciones en el prompt.
- Compilar con cargo puede tardar 1-2 minutos la primera vez.

## Licencia

MIT
