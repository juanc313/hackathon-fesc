# Terminal Rescue — Cierre mensual de afiliados activos

## Descripción

Este software repara y completa el cierre mensual de afiliados activos que Operaciones ejecuta para el área de Subsidios de la caja de compensación. Parte de los CSV del sistema origen (afiliados, beneficiarios, empresas y aportes), los cruza con el extracto enviado por Caja Oriente y produce el archivo de afiliados activos que consume Subsidios, el informe de excepciones, los totales del cierre y el error más frecuente de los logs. Lo usan Operaciones y Auditoría para conciliar el mes y para detectar datos sucios sin descartar ningún registro en silencio.

## Integrantes

- Juan Camilo Sandoval Uribe — reparación del entorno, cierre de afiliados y documentación.
- Modalidad de trabajo: equipo unipersonal (no hubo segundo integrante).

## Requisitos

Docker con Docker Compose (Docker Desktop en Windows, o `docker.io` y el plugin `docker compose` en Linux). El kit ya trae los datos de prueba en `data/`, así que no hace falta instalar Python, PostgreSQL ni ninguna otra dependencia por fuera de Docker.

## Instalación y ejecución

Desde una copia limpia del repositorio:

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps
./run.sh
```

`docker compose up -d --build` levanta la base de datos, la API y el worker, y `./run.sh` ejecuta el cierre y deja los cuatro archivos en `output/`. Si el entorno queda a medias, `./reset.sh` lo devuelve al estado inicial, recarga la base desde `data/` y borra la carpeta de salida. El entorno levanta incluso sin `.env`: cada variable de `docker-compose.yml` se declara como `${VARIABLE:-predeterminado}`, así que `docker compose up -d --build` funciona desde una copia limpia y `.env` solo sirve para cambiar esos valores.

## Configuración

Todas las variables se leen del archivo `.env` (se entrega `.env.example`; el `.env` real no se versiona porque está en `.gitignore`). Cada una se declara también en `docker-compose.yml` como `${VARIABLE:-predeterminado}`, de modo que si `.env` no existe el entorno igual levanta con esos valores predeterminados.

| Variable | Para qué sirve | Valor de ejemplo |
| --- | --- | --- |
| `POSTGRES_DB` | Nombre de la base que crea el contenedor `cierre-db`. | `cierre` |
| `POSTGRES_USER` | Usuario administrador de PostgreSQL. | `cierre` |
| `POSTGRES_PASSWORD` | Contraseña del usuario administrador de la base. | el que trae `.env.example` |
| `DATABASE_HOST` | Host que usan la API y el worker: es el nombre del servicio `cierre-db`, no un host externo. | `cierre-db` |
| `DATABASE_PORT` | Puerto de PostgreSQL dentro de la red de Compose. | `5432` |
| `DATABASE_NAME` | Base a la que se conectan la API y el worker. | `cierre` |
| `DATABASE_USER` | Usuario con el que se conectan la API y el worker. | `cierre` |
| `DATABASE_PASSWORD` | Contraseña de ese usuario; debe coincidir con la de PostgreSQL. | el que trae `.env.example` |
| `API_PORT` | Puerto del host donde queda publicada la API. | `8081` |
| `WORKER_INTERVAL_SECONDS` | Cada cuántos segundos concilia el worker; debe ser un entero de segundos. | `30` |

## Arquitectura

El entorno se compone de tres servicios declarados en `docker-compose.yml`. `cierre-db` es un PostgreSQL 16 que al crearse ejecuta el esquema de `db/init/01_schema.sql` y carga los CSV montados en `/data`. `cierre-api` es un servidor HTTP en Python que expone la consulta de afiliados en el puerto 8081 y lee la base con `psycopg2`. `cierre-worker` es un proceso Python que cada `WORKER_INTERVAL_SECONDS` concilia en la base el total de registros contra los documentos distintos y registra el resultado en su log. El cierre es aparte: `run.sh` llama a `scripts/cierre.sh`, que corre en el host, lee los CSV de `data/`, cuenta los errores de `logs/` y escribe la carpeta `output/`.

## Uso

La ruta de consulta del contrato es `GET /afiliados/{documento}`, por ejemplo:

```bash
curl http://localhost:8081/afiliados/1098765432
```

Responde `{"documento": "1098765432", "nombre": "JUAN CARLOS PEREZ GOMEZ", "estado": "ACTIVO", "empresa": "EMPRESA ABC"}` y un documento que no existe responde 404.

Al ejecutar `./run.sh` se generan estos archivos en `output/`:

| Archivo | Contenido |
| --- | --- |
| `afiliados_activos.csv` | Un renglón por afiliado activo con empresa válida: documento, nombre, estado, cod_empresa, empresa, beneficiarios y ultimo_aporte. |
| `excepciones.csv` | documento, tipo y detalle de cada novedad: DUPLICADO, SIN_EMPRESA, BENEFICIARIO_HUERFANO, CODIGO_INVALIDO, FECHA_INVALIDA y CRUCE_NO_COINCIDE. |
| `totales.txt` | Las claves total_afiliados, activos, inactivos y excepciones del cierre. |
| `top_error.txt` | El código de error más frecuente de los logs y cuántas veces aparece. |

## Pruebas

Levanta el entorno con `docker compose up -d --build` y ejecuta `./validator check --quick` para ver las pruebas públicas del contrato. Después corre `./run.sh` dos veces seguidas: los cuatro archivos de `output/` deben salir idénticos en las dos corridas y `output/totales.txt` debe coincidir con `control/hoja_control.csv`. También puedes consultar la API por HTTP y comprobar que un documento inexistente responde 404.

## Documentación

- [incident-report.md](incident-report.md) — informe de los diez incidentes, con su diagnóstico y sus comandos.
- [evidence/](evidence/) — salida de terminal que demuestra cada diagnóstico, un archivo por incidente.
- [AI_USAGE.md](AI_USAGE.md) — registro de cómo se usó la inteligencia artificial durante el reto.

## Qué resolvimos

Encontramos y corregimos los diez incidentes del kit. El worker salía con error porque `WORKER_INTERVAL_SECONDS` traía `30s`; la API no conectaba porque `DATABASE_HOST` apuntaba a un host que no existe; el cierre heredado leía una ruta inexistente, creaba su carpeta sin `-p` y movía su propia entrada; y la consulta de afiliados fallaba con 500 por los campos vacíos y un `JOIN` mal armado. Completamos el cierre para que normalice fechas, cruce el extracto de Caja Oriente y reporte duplicados, afiliados sin empresa, beneficiarios huérfanos y códigos inválidos. Al final los totales cuadran con la hoja de control, el cierre es repetible y el entorno queda levantable desde cero con `docker compose up -d --build` aunque no exista `.env`.

## Limitaciones y pendientes

En este equipo no estaba instalado Docker, por lo que `docker compose up -d` y `./validator check` no se pudieron ejecutar localmente contra los contenedores en vivo (las correcciones de `cierre-worker`, `cierre-api` y `.env.example` se verificaron sobre el código, los logs y los hashes de `.validator.json`). La normalización de fechas cubre los tres formatos del diccionario, así que un formato nuevo habría que agregarlo al script. El cierre corre en el host y no dentro de un contenedor, porque trabaja directamente sobre los CSV del repositorio y la carpeta `logs/`. El video del pitch de un minuto y el registro del repositorio público en la plataforma del evento quedan fuera del alcance del código.
