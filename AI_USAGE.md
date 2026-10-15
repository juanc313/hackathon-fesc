# Uso de inteligencia artificial

## Uso 1

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: entender por qué el contenedor `cierre-worker` quedaba en `Exited (1)` al levantar el entorno.
- Prompt principal (resumido): "el worker de docker compose sale con código 1; revisa worker.py y el .env del kit"
- Qué produjo: señaló que `load_interval()` hace `int()` sobre `WORKER_INTERVAL_SECONDS` y que el valor del kit traía un sufijo.
- Qué modificó o corrigió el equipo: verifiqué con grep que el valor era `30s`, confirmé que el resto del `.env.example` estaba bien y lo cambié a `30` sin sufijos.

## Uso 2

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: reescribir el cierre heredado en Bash para que leyera los CSV de `data/` y generara los cuatro archivos de `output/`.
- Prompt principal (resumido): "el script de cierre apunta a /opt/cierre/entrada y mueve el CSV; hazlo repetible en bash"
- Qué produjo: un `scripts/cierre.sh` con varias etapas de awk que separan duplicados, excepciones y totales.
- Qué modificó o corrigió el equipo: al ejecutarlo, el encabezado de `afiliados_activos.csv` desaparecía porque el signo `>` de awk truncó el archivo ya escrito; se cambió a `>>`.

## Uso 3

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: diagnosticar por qué `GET /afiliados/{documento}` devolvía 500 en unos afiliados y 404 en otros que sí existen.
- Prompt principal (resumido): "la consulta de afiliados responde 500 en la API y algunos documentos válidos dan 404"
- Qué produjo: sugirió revisar la conexión a la base y el manejo de los campos del registro.
- Qué modificó o corrigió el equipo: en `db/init/02_load.sql` vi que `\copy` carga los campos vacíos como NULL y que `nom1 + " " + nom2` lanza TypeError; se cambió el `JOIN` por `LEFT JOIN` con `COALESCE` y el mapeo de estado a `ESTADOS.get`, comprobando contra los hashes de `.validator.json`.

## Uso 4

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: interpretar el extracto de Caja Oriente, que trae otras columnas, otro separador y otro formato de fecha.
- Prompt principal (resumido): "el extracto de caja oriente tiene columnas distintas; cómo cruzarlo sin romper el archivo de activos"
- Qué produjo: propuso normalizar el documento quitando los ceros de la izquierda y mapear `VIGENTE`/`RETIRADO` contra nuestro `EST_AFI`.
- Qué modificó o corrigió el equipo: se ajustó el cruce para reportar en `CRUCE_NO_COINCIDE` tanto los documentos que no existen como los que tienen situación distinta, comprobando que quedaran 25 casos.

## Uso 5

- Herramienta: Claude (Anthropic)
- Para qué se usó: pedir una segunda opinión sobre el trabajo hecho con Freebuff antes de entregar el repositorio.
- Prompt principal (resumido): "creo que ya está hecho por Freebuff, míralo y dime qué falta o qué corregirías"
- Qué produjo: por iniciativa propia revisó el kit, ejecutó `run.sh` dos veces para comprobar totales y `top_error`, y señaló que Docker no se había probado en este equipo, que en `evidence/` había textos de pendiente y que `incident-report.md` listaba `docker` y `psql` sin haberlos corrido.
- Qué modificó o corrigió el equipo: revisé las observaciones, pedí quitar de `incident-report.md` y de `evidence/` cualquier comando de Docker no ejecutado, anoté en el `README.md` que Docker no se probó localmente y revisé `git diff` y `git status` antes de hacer mis propios commits.
