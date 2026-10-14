# Informe de incidentes — Terminal Rescue

## Incidente 1

- **Síntoma:** `docker compose ps` mostraba `cierre-worker` en `Exited (1)` y el worker no volvía a levantarse solo.
- **Diagnóstico:** el worker lee `WORKER_INTERVAL_SECONDS` y le aplica `int()`; con el valor `30s` la conversión falla, registra `CIE-1107` y termina con código 1.
- **Comandos:** `docker compose ps`, `docker compose logs cierre-worker | tail -5`, `grep -n WORKER_INTERVAL_SECONDS .env.example`
- **Solución:** se dejó `WORKER_INTERVAL_SECONDS=30` (entero de segundos, sin sufijos) en `.env.example` y se recreó el contenedor del worker.
- **Evidencia:** evidence/01-worker.txt

## Incidente 2

- **Síntoma:** la API respondía 503 y en los logs aparecía `CIE-2210` con "no hay conexión con la base de datos".
- **Diagnóstico:** `DATABASE_HOST` apuntaba a `cierre-database`, pero el servicio de `docker-compose.yml` se llama `cierre-db`; dentro de la red de Compose los contenedores solo se resuelven por nombre de servicio.
- **Comandos:** `grep -n DATABASE_HOST .env.example`, `docker compose logs cierre-api | tail -5`, `docker compose exec cierre-db psql -U cierre -d cierre -c "\l"`
- **Solución:** se cambió `DATABASE_HOST=cierre-db` en `.env.example` (y en `.env`) y se recrearon los servicios para que tomaran el valor nuevo.
- **Evidencia:** evidence/02-api-db.txt

## Incidente 3

- **Síntoma:** el cierre terminaba sin leer los afiliados y en la segunda ejecución fallaba al crear su carpeta de salida.
- **Diagnóstico:** el script heredado apuntaba a `/opt/cierre/entrada`, hacía `mkdir $SALIDA` sin `-p` y movía `AFI_MAE.csv` a `procesados/`, así que la entrada desaparecía.
- **Comandos:** `grep -n ENTRADA scripts/cierre.sh`, `ls /opt/cierre/entrada`, `find data -type f`, `chmod +x run.sh scripts/cierre.sh`
- **Solución:** el cierre lee los CSV desde `data/`, crea la salida con `mkdir -p output` y ya no mueve ni borra los archivos de entrada.
- **Evidencia:** evidence/03-cierre-rutas.txt

## Incidente 4

- **Síntoma:** los tres logs sumaban 11.515 líneas y no era evidente cuál error era el dominante.
- **Diagnóstico:** al extraer los códigos `CIE-####` y contarlos, el más frecuente es `CIE-4012` con 1424 ocurrencias en total, muy por encima de `CIE-5003` y `CIE-2210`.
- **Comandos:** `wc -l logs/*.log`, `grep -hoE 'CIE-[0-9]{4}' logs/*.log | sort | uniq -c | sort -k1,1nr | head -1`
- **Solución:** `run.sh` ahora genera `output/top_error.txt` con `codigo_error=CIE-4012` y `ocurrencias=1424`.
- **Evidencia:** evidence/04-top-error.txt

## Incidente 5

- **Síntoma:** los totales salían inflados y había beneficiarios y afiliados que no correspondían a ninguna empresa.
- **Diagnóstico:** el maestro trae 20 documentos repetidos, 18 activos sin empresa válida, 15 beneficiarios huérfanos y 14 códigos de estado distintos de `A` e `I`.
- **Comandos:** `awk -F',' 'NR>1 {print $1}' data/AFI_MAE.csv | sort | uniq -d | wc -l`, `awk -F',' 'NR>1 {print $7}' data/AFI_MAE.csv | sort | uniq -c`, `docker compose exec cierre-db psql -U cierre -d cierre -c "SELECT count(*), count(DISTINCT nro_doc) FROM afi_mae"`
- **Solución:** el cierre conserva la primera aparición de cada documento, excluye de los activos a quien no tiene empresa y reporta las seis clases de excepción en `output/excepciones.csv`.
- **Evidencia:** evidence/05-calidad-datos.txt

## Incidente 6

- **Síntoma:** `GET /afiliados/{documento}` respondía 500 (`CIE-5003`) y algunos afiliados con empresa válida salían como 404.
- **Diagnóstico:** los campos opcionales vacíos del CSV llegan como NULL y `nom1 + " " + nom2` lanzaba `TypeError`; además el `JOIN` con `empresa` descartaba afiliados sin empresa y `ESTADOS[est_afi]` lanzaba `KeyError` con un estado inválido.
- **Comandos:** `docker compose logs cierre-api | grep CIE-5003 | tail -5`, `sed -n '22,31p' services/api/app.py`, `curl -s http://localhost:8081/afiliados/3756530718`
- **Solución:** se toleran los NULL al armar el nombre, se usa `LEFT JOIN` con `COALESCE` sobre la empresa y un mapeo de estado sin excepciones; la consulta responde 200 y 404 como pide el contrato.
- **Evidencia:** evidence/06-api-500.txt

## Incidente 7

- **Síntoma:** el cierre no entendía varias fechas de afiliación y algunos registros desaparecían sin aviso.
- **Diagnóstico:** `FEC_AFI` mezcla `YYYY-MM-DD`, `DD/MM/YYYY` y `YYYYMMDD`, y trae valores que no son fechas reales (`31/13/2024`, `00000000`, `N/A`, `SIN FECHA`, `2023/02/29`).
- **Comandos:** `awk -F',' 'NR>1 {print $9}' data/AFI_MAE.csv | sed -E 's/[0-9]/9/g' | sort | uniq -c`, `grep FECHA_INVALIDA output/excepciones.csv`
- **Solución:** el cierre acepta los tres formatos, valida día, mes y año bisiesto, y reporta `FECHA_INVALIDA` sin descartar el registro de los totales.
- **Evidencia:** evidence/07-fechas.txt

## Incidente 8

- **Síntoma:** el extracto de Caja Oriente no encajaba con el maestro y el cruce no se reportaba por ningún lado.
- **Diagnóstico:** ese archivo usa `;` como separador, documentos de 12 dígitos rellenos con ceros, fechas `DD/MM/YYYY` y una columna `situacion` con `VIGENTE` o `RETIRADO` en lugar de nuestro `EST_AFI`.
- **Comandos:** `head -2 data/extracto_caja_oriente.csv`, `grep CRUCE_NO_COINCIDE output/excepciones.csv`, `awk -F';' 'NR>1 {print $3}' data/extracto_caja_oriente.csv | sort | uniq -c`
- **Solución:** el cierre quita los ceros de la izquierda, compara la situación del extracto con el estado local y reporta 25 casos `CRUCE_NO_COINCIDE`, conservando el formato del archivo de activos.
- **Evidencia:** evidence/08-cruce.txt

## Incidente 9

- **Síntoma:** los totales del cierre no cuadraban con la hoja de control de Operaciones.
- **Diagnóstico:** el script heredado solo contaba activos con `wc -l` sobre su propia salida y nunca calculaba los inactivos ni las excepciones.
- **Comandos:** `cat control/hoja_control.csv`, `cat output/totales.txt`, `grep '^activos=' output/totales.txt`, `wc -l output/excepciones.csv`
- **Solución:** `output/totales.txt` queda en `total_afiliados=1500`, `activos=1194`, `inactivos=274` y `excepciones=104`, y las tres primeras claves coinciden con la hoja de control.
- **Evidencia:** evidence/09-totales.txt

## Incidente 10

- **Síntoma:** el cierre solo funcionaba la primera vez; al repetirlo fallaba porque su archivo de entrada ya no estaba.
- **Diagnóstico:** el script movía `AFI_MAE.csv` a `procesados/`, usaba `mkdir` sin `-p` y reescribía la salida de forma no idempotente, así que dos corridas seguidas no daban el mismo resultado.
- **Comandos:** `./run.sh`, `diff -r /tmp/cierre-primera output`, `./reset.sh`, `ls data/ | wc -l`
- **Solución:** el cierre deja la entrada intacta y reconstruye `output/` desde cero, así que dos ejecuciones consecutivas producen salidas idénticas y también funciona después de `./reset.sh`.
- **Evidencia:** evidence/10-repetibilidad.txt
