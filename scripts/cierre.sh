#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Cierre mensual de afiliados activos — Terminal Rescue.
#
# Reparación del cierre heredado de Operaciones:
#   * Lee la entrada real del repositorio (data/), no /opt/cierre/entrada.
#   * No mueve ni borra los archivos de entrada: crear output/ con -p y dejar
#     la entrada intacta hace que el cierre sea repetible (se puede correr
#     dos veces seguidas y también después de ./reset.sh).
#   * Completa los TODO pendientes: nombre de la empresa, beneficiarios,
#     último aporte, excepciones, cruce con Caja Oriente, totales y el error
#     más frecuente de los logs.
#
# Reglas aplicadas: docs/diccionario.md (sección «Reglas del cierre»).
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

ENTRADA="${ENTRADA:-data}"
SALIDA="${SALIDA:-output}"
LOGSDIR="${LOGSDIR:-logs}"

MAE="$ENTRADA/AFI_MAE.csv"
BEN="$ENTRADA/AFI_BEN.csv"
EMP="$ENTRADA/EMPRESA.csv"
APO="$ENTRADA/APORTES.csv"
CRU="$ENTRADA/extracto_caja_oriente.csv"

for archivo in "$MAE" "$BEN" "$EMP" "$APO" "$CRU"; do
    if [ ! -r "$archivo" ]; then
        echo "CIE-3301 no se puede leer el archivo de entrada: $archivo" >&2
        exit 1
    fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$SALIDA"
mkdir -p "$SALIDA"

# ---------------------------------------------------------------------------
# 1. Universo: un registro por documento distinto (se conserva la primera
#    aparición). Cada documento repetido se reporta una sola vez como
#    DUPLICADO.
# ---------------------------------------------------------------------------
awk -F',' -v unico="$TMP/unico.csv" -v dup="$TMP/duplicados" '
    NR > 1 {
        if ($1 in visto) {
            if (!($1 in repetido)) { repetido[$1] = 1; print $1 > dup }
        } else {
            visto[$1] = 1
            print $0 > unico
        }
    }
' "$MAE"

# ---------------------------------------------------------------------------
# 2. Estados válidos (A/I), empresa, beneficiarios y último aporte.
#    Un activo con COD_EMP vacío o inexistente no entra al archivo de activos
#    ni al total de activos: se reporta SIN_EMPRESA.
# ---------------------------------------------------------------------------
echo "documento,nombre,estado,cod_empresa,empresa,beneficiarios,ultimo_aporte" > "$TMP/activos.csv"

awk -F',' \
    -v EMPFILE="$EMP" -v BENFILE="$BEN" -v APOFILE="$APO" \
    -v SESALIDA="$TMP/sin_empresa" -v ACTIVOS="$TMP/activos.csv" '
    function campos(linea, destino) {
        # Separa respetando el CSV simple del kit.
        return split(linea, destino, ",")
    }

    BEGIN {
        while ((getline linea < EMPFILE) > 0) {
            split(linea, c, ",")
            if (c[1] == "COD_EMP") continue
            empresa[c[1]] = c[2]
        }
        close(EMPFILE)

        while ((getline linea < BENFILE) > 0) {
            split(linea, c, ",")
            if (c[2] == "NRO_DOC_AFI") continue
            benef[c[2]]++
        }
        close(BENFILE)

        while ((getline linea < APOFILE) > 0) {
            split(linea, c, ",")
            if (c[1] == "NRO_DOC") continue
            if (!(c[1] in ultimo) || c[2] > ultimo[c[1]]) ultimo[c[1]] = c[2]
        }
        close(APOFILE)
    }

    {
        doc = $1
        if ($7 != "A") next
        if ($8 == "" || !($8 in empresa)) {
            detalle = ($8 == "") ? "cod_emp vacio" : "cod_emp " $8 " no existe en EMPRESA"
            print doc ",SIN_EMPRESA," detalle > SESALIDA
            next
        }
        nombre = $3
        if ($4 != "") nombre = nombre " " $4
        if ($5 != "") nombre = nombre " " $5
        if ($6 != "") nombre = nombre " " $6
        print doc "," nombre ",ACTIVO," $8 "," empresa[$8] "," \
              (doc in benef ? benef[doc] : 0) "," (doc in ultimo ? ultimo[doc] : "") >> ACTIVOS
    }
' "$TMP/unico.csv"

# ---------------------------------------------------------------------------
# 3. Códigos de estado inválidos (solo A e I son válidos): el afiliado no
#    cuenta como activo ni como inactivo.
# ---------------------------------------------------------------------------
awk -F',' '$7 != "A" && $7 != "I" { print $1 ",CODIGO_INVALIDO,est_afi=" $7 }' \
    "$TMP/unico.csv" > "$TMP/codigo_invalido"

# ---------------------------------------------------------------------------
# 4. Fechas de afiliación: YYYY-MM-DD, DD/MM/YYYY y YYYYMMDD se aceptan; una
#    fecha que no es una fecha real se reporta FECHA_INVALIDA (el registro
#    nunca se descarta en silencio).
# ---------------------------------------------------------------------------
awk -F',' '
    function bisiesto(anio) {
        return (anio % 4 == 0 && anio % 100 != 0) || anio % 400 == 0
    }
    function dias_del_mes(mes, anio) {
        if (mes == 2) return bisiesto(anio) ? 29 : 28
        if (mes == 4 || mes == 6 || mes == 9 || mes == 11) return 30
        return 31
    }
    function fecha_valida(texto,   a, anio, mes, dia) {
        if (texto ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
            split(texto, a, "-"); anio = a[1] + 0; mes = a[2] + 0; dia = a[3] + 0
        } else if (texto ~ /^[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9][0-9][0-9]$/) {
            split(texto, a, "/"); dia = a[1] + 0; mes = a[2] + 0; anio = a[3] + 0
        } else if (texto ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) {
            anio = substr(texto, 1, 4) + 0; mes = substr(texto, 5, 2) + 0; dia = substr(texto, 7, 2) + 0
        } else {
            return 0
        }
        if (mes < 1 || mes > 12) return 0
        if (dia < 1 || dia > dias_del_mes(mes, anio)) return 0
        return 1
    }
    { if (!fecha_valida($9)) print $1 ",FECHA_INVALIDA,fec_afi=" $9 }
' "$TMP/unico.csv" > "$TMP/fecha_invalida"

# ---------------------------------------------------------------------------
# 5. Beneficiarios huérfanos: su afiliado no existe en AFI_MAE. La columna
#    documento lleva el documento del beneficiario.
# ---------------------------------------------------------------------------
awk -F',' -v UNICO="$TMP/unico.csv" '
    BEGIN {
        while ((getline linea < UNICO) > 0) {
            split(linea, c, ",")
            universo[c[1]] = 1
        }
        close(UNICO)
    }
    NR > 1 { if (!($2 in universo)) print $1 ",BENEFICIARIO_HUERFANO,afiliado " $2 " no existe en AFI_MAE" }
' "$BEN" > "$TMP/huerfanos"

# ---------------------------------------------------------------------------
# 6. Cruce con Caja Oriente: su extracto usa ';' y documentos de 12 dígitos
#    rellenos con ceros. Si el documento no está en AFI_MAE o la situación no
#    corresponde a nuestro estado, se reporta CRUCE_NO_COINCIDE. El archivo de
#    activos conserva su formato; este extracto solo alimenta excepciones.
# ---------------------------------------------------------------------------
awk -v UNICO="$TMP/unico.csv" '
    BEGIN {
        FS = ","
        while ((getline linea < UNICO) > 0) {
            split(linea, c, ",")
            estado[c[1]] = c[7]
        }
        close(UNICO)
        FS = ";"
    }
    NR > 1 {
        doc = $1
        sub(/^0+/, "", doc)
        situacion = $3
        esperado = (situacion == "VIGENTE") ? "A" : ((situacion == "RETIRADO") ? "I" : "?")
        if (!(doc in estado)) {
            print doc ",CRUCE_NO_COINCIDE,no existe en AFI_MAE (extracto dice " situacion ")"
        } else if (estado[doc] != esperado) {
            print doc ",CRUCE_NO_COINCIDE,situacion " situacion " no coincide con el estado " estado[doc]
        }
    }
' "$CRU" > "$TMP/cruce"

# ---------------------------------------------------------------------------
# 7. Archivo de excepciones (un renglón por caso, ordenado y determinista).
# ---------------------------------------------------------------------------
cat "$TMP/codigo_invalido" "$TMP/sin_empresa" "$TMP/fecha_invalida" \
    "$TMP/huerfanos" "$TMP/cruce" > "$TMP/bloques.csv"
sed 's/$/,DUPLICADO,documento repetido en AFI_MAE/' "$TMP/duplicados" >> "$TMP/bloques.csv"
sort -t',' -k1,1 -k2,2 "$TMP/bloques.csv" -o "$TMP/bloques.csv"

echo "documento,tipo,detalle" > "$SALIDA/excepciones.csv"
cat "$TMP/bloques.csv" >> "$SALIDA/excepciones.csv"

# Archivo de activos ordenado por documento y con el encabezado del contrato.
{
    head -n 1 "$TMP/activos.csv"
    tail -n +2 "$TMP/activos.csv" | sort -t',' -k1,1
} > "$SALIDA/afiliados_activos.csv"

# ---------------------------------------------------------------------------
# 8. Totales del cierre.
# ---------------------------------------------------------------------------
TOTAL_AFILIADOS=$(wc -l < "$TMP/unico.csv" | tr -d ' ')
ACTIVOS=$(tail -n +2 "$SALIDA/afiliados_activos.csv" | wc -l | tr -d ' ')
INACTIVOS=$(awk -F',' '$7 == "I"' "$TMP/unico.csv" | wc -l | tr -d ' ')
EXCEPCIONES=$(tail -n +2 "$SALIDA/excepciones.csv" | wc -l | tr -d ' ')

{
    echo "total_afiliados=$TOTAL_AFILIADOS"
    echo "activos=$ACTIVOS"
    echo "inactivos=$INACTIVOS"
    echo "excepciones=$EXCEPCIONES"
} > "$SALIDA/totales.txt"

# ---------------------------------------------------------------------------
# 9. Error más frecuente en los logs (los avisos W-### no son errores).
# ---------------------------------------------------------------------------
CODIGO_ERROR=""
OCURRENCIAS=0
if compgen -G "$LOGSDIR/*.log" > /dev/null; then
    TOP="$(grep -hoE 'CIE-[0-9]{4}' "$LOGSDIR"/*.log | sort | uniq -c \
        | sort -k1,1nr -k2,2 | head -n 1 || true)"
    if [ -n "$TOP" ]; then
        OCURRENCIAS="$(echo "$TOP" | awk '{print $1}')"
        CODIGO_ERROR="$(echo "$TOP" | awk '{print $2}')"
    fi
fi

{
    echo "codigo_error=$CODIGO_ERROR"
    echo "ocurrencias=$OCURRENCIAS"
} > "$SALIDA/top_error.txt"

echo "Cierre terminado"
echo "  total_afiliados=$TOTAL_AFILIADOS activos=$ACTIVOS inactivos=$INACTIVOS excepciones=$EXCEPCIONES"
echo "  error más frecuente: ${CODIGO_ERROR:-ninguno} (${OCURRENCIAS} ocurrencias)"
