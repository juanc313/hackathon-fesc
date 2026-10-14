# Uso de inteligencia artificial

## Uso 1

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: entender por qué el contenedor `cierre-worker` quedaba en `Exited (1)` al levantar el entorno.
- Prompt principal: "el worker de docker compose sale con código 1; revisa worker.py y el .env del kit"
- Qué produjo: señaló que `load_interval()` hace `int()` sobre `WORKER_INTERVAL_SECONDS` y que el valor del kit traía un sufijo.
- Qué modificó o corrigió el equipo: verificamos con grep que el valor era `30s`, confirmamos que el resto del .env estaba bien y lo cambiamos a `30` sin sufijos.

## Uso 2

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: reescribir el cierre heredado en Bash para que leyera los CSV de `data/` y generara los cuatro archivos de `output/`.
- Prompt principal: "el script de cierre apunta a /opt/cierre/entrada y mueve el CSV; hazlo repetible en bash"
- Qué produjo: un `scripts/cierre.sh` con varias etapas de awk que separan duplicados, excepciones y totales.
- Qué modificó o corrigió el equipo: al ejecutarlo, el encabezado de `afiliados_activos.csv` desaparecía, porque el signo `>` de awk truncó el archivo ya escrito; lo cambiamos a `>>`.

## Uso 3

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: diagnosticar por qué `GET /afiliados/{documento}` devolvía 500 en unos afiliados y 404 en otros que sí existen.
- Prompt principal: "la consulta de afiliados responde 500 en la API y algunos documentos válidos dan 404"
- Qué produjo: sugirió revisar la conexión a la base y el manejo de los campos del registro.
- Qué modificó o corrigió el equipo: probamos que los campos vacíos llegan como NULL y que `nom1 + " " + nom2` lanza TypeError; además cambiamos el `JOIN` por `LEFT JOIN` con `COALESCE` y el mapeo de estado a `ESTADOS.get`.

## Uso 4

- Herramienta: Freebuff (agente de código con IA)
- Para qué se usó: interpretar el extracto de Caja Oriente, que trae otras columnas, otro separador y otro formato de fecha.
- Prompt principal: "el extracto de caja oriente tiene columnas distintas; cómo cruzarlo sin romper el archivo de activos"
- Qué produjo: propuso normalizar el documento quitando los ceros de la izquierda y mapear `VIGENTE`/`RETIRADO` contra nuestro `EST_AFI`.
- Qué modificó o corrigió el equipo: ajustamos el cruce para reportar en `CRUCE_NO_COINCIDE` tanto los documentos que no existen como los que tienen situación distinta, y comprobamos que quedaran 25 casos.
