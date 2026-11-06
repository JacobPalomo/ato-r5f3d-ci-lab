# ATO v0.6 · R5F-3D — CI efímero para smoke REAL de Rails (solo datos sintéticos)

> **No ejecutar en el Mac local.** R5F-3C devuelve `BLOCK_LOCAL_CLONE`: 3.83 GiB RAM Docker / 4.72 GiB libres. No tocar `ato-v06-staging`, `ato-chatwoot-n8n-lab`, v0.5.2, Gateway, bases operativas, `.env` o credenciales. Este paquete NO contiene datos de clientes.

## Alcance exacto

R5F-3D es el **primer smoke de runtime Rails** propuesto, en un runner ARM64 de GitHub Actions que desaparece al terminar. Incluye una instancia Chatwoot `chatwoot/chatwoot:v4.19.0`, PostgreSQL/pgvector **nuevo** y Redis **nuevo**, dentro de una red Docker `internal: true`, sin puertos expuestos ni acceso externo desde Rails. Usa únicamente contraseña y secreto temporales generados para la CI (sin secretos GitHub).

**La imagen de Chatwoot se verifica por su ID exacto `sha256:efb1f9fa48a922e74ce7960d44830d7d4d61764bb2295f9bca9d1470cce18275`**. Este ID es el de la imagen ARM64 auditada de tu Mac. Si la etiqueta fue cambiada, la prueba falla **antes** de crear la DB. Nunca usar `latest`.

**No demuestra**: parche Rails instalado, RSpec, transacción de idempotencia/fencing en Chatwoot, Sidekiq de salida, WhatsApp, atomicidad entre PostgreSQL ATO y Chatwoot, ni exactly-once del proveedor.

## Antes de ejecutar

- Este es un flujo MANUAL (`workflow_dispatch`), no se inicia al hacer push.
- Debes crear **un repositorio de prueba nuevo y separado**, sin archivos ni datos de ATO. Puede ser público si solo contiene este paquete técnico sin secretos; si es privado, revisa tu cuota y eventual facturación de GitHub Actions. No reutilizar repos operativos.
- `ubuntu-24.04-arm` en repos públicos dispone de 16 GiB RAM / 14 GiB SSD según documentación GitHub consultada 2026-11-06; en privados podría tener menos recursos y consumir minutos. El flujo **mide y bloquea** por debajo de 6 GiB RAM o 10 GiB SSD libre antes de descargar imágenes. También podría fallar por disco después de las descargas; esto no es éxito.
- La descarga de imágenes públicas requiere Internet en el host CI; la red de Rails/DB/Redis es interna.
- No configures `api_access_token`, token de Meta, `DATABASE_URL` real, `.env`, ni ningún secreto de cliente. No abras puertos ni cambies `internal: true`.

## 1. Pruebas LOCALES del paquete (seguras)

En el Mac, tras descomprimir en `~/Downloads`:

```bash
python3 -m unittest discover \
  -s ~/Downloads/ATO_v06_Fase7C_R5F3D_Rails_Runtime_Smoke_CI_AISLADO/tests -v
```

Estas pruebas son estructurales: NO ejecutan Docker ni Rails. Deben terminar en `OK`. El lanzador `scripts/run_r5f3d_ci.sh` rechaza ejecución local.

## 2. Crear repositorio técnico exclusivo

En GitHub, crea un **repositorio nuevo vacío** con un nombre como `ato-r5f3d-ci-lab`; no uses un repositorio operativo. La visibilidad (pública/privada) depende de ti. El archivo en `.github/workflows/r5f3d-smoke.yml` debe estar en la rama por defecto para que aparezca el botón **Run workflow**.

Solo sube estos elementos del ZIP:

```
.github/workflows/r5f3d-smoke.yml
docker-compose.r5f3d.yaml
rails/r5f3d_smoke.rb
scripts/run_r5f3d_ci.sh
scripts/report_r5f3d.py
.gitignore
README.md
```

No subas los JSON de evidencia previos ni `.env`. Si tu cuenta/organización deshabilitó Actions, deberás habilitarlo manualmente. No es necesario permitir permisos de escritura para `GITHUB_TOKEN`.

## 3. Ejecutar

En GitHub, `Actions` → `R5F-3D - Chatwoot Rails isolated smoke` → `Run workflow`. No se ejecuta solo; la ejecución tiene un límite de 45 minutos.

El script hará:

1. Comprobar que **está en un runner GitHub-hosted ARM64**, con entorno y workspace esperados; bloquear usos locales.
2. Comprobar RAM y SSD libre; bloquear por debajo del umbral.
3. Comprobar que no existe ya un contenedor con el nombre de proyecto de pruebas.
4. Descargar `chatwoot/chatwoot:v4.19.0` y comprobar **el image ID ARM64 exacto**.
5. Descargar Postgres con pgvector y Redis; iniciar ambos **vacíos** en una red interna sin puertos publicados.
6. Ejecutar `bundle exec rails db:chatwoot_prepare` sobre la DB sintética vacía **antes** del primer `rails runner`.
7. Comprobar con una consulta SQL de solo lectura que existen `installation_configs`, `messages`, `conversations` y `accounts`; si falta alguna, detenerse sin declarar el esquema listo.
8. Ejecutar `bundle exec rails runner` para verificar el arranque con el esquema ya preparado.
9. Cargar el runner Ruby de inspección de tablas y del índice no único `source_id`.
10. Apagar Compose, eliminar volúmenes, generar JSON y subirlo como artefacto incluso si el job falla.

**Importante:** la base se llama `chatwoot_production` **solo dentro del CI efímero** para ser compatible con el setup de la imagen. Nunca se conecta a ninguna base operativa. Si `db:chatwoot_prepare` falla por variables o por la instalación de la imagen, el diagnóstico se reporta como fallo real, no se salta el paso.

## 4. Recoger evidencia

Descarga el artefacto `ato-r5f3d-smoke-report` y el log del job. El JSON indica `passed`, `last_step`, `image_id_verified`, `rails_executed`, `database_schema_ready`, `cleanup_completed`, y banderas explícitamente falsas sobre RSpec, Sidekiq, WhatsApp y el parche.

- Si `passed=true` y `last_step=SMOKE_PASS`: Rails arrancó y el esquema se inicializó en CI. **NO es PASS del parche**.
- Si `passed=false`: entrega el JSON y las líneas del log alrededor del primer ERROR; no reintentes sin diagnosticar.
- Si `cleanup_completed=false`: el runner es efímero, pero el teardown requiere revisión; no certificar cierre.

## Decisión después de R5F-3D

Si el runtime arranca, el próximo hito **R5F-3E** será integrar una versión funcional mínima del parche (en un fork/copias de código SOLO CI), ejecutar RSpec con `RAILS_ENV=test`, y cubrir idempotencia, fencing y handoff con PostgreSQL en transacciones reales. Este paquete **NO incluye esos tests** porque primero debemos confirmar el entorno Rails real; no presentar una prueba de humo como garantía de entrega.

Si falla el setup por recursos, usar un runner/VM mayor, pero NUNCA apagar el laboratorio operativo para acomodar el clon.
