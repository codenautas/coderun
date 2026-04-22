#!/bin/bash

echo "=== Clonador de Entornos YAML (App + Pass DB) ==="

# 1. Nombres de operativos
read -p "Nombre operativo ORIGEN (ej. prrepsic252): " ORIGEN_FULL
read -p "Nombre operativo DESTINO (ej. prrepsic261): " DESTINO_FULL

FILE_ORIGEN="${ORIGEN_FULL}.yaml"
FILE_DESTINO="${DESTINO_FULL}.yaml"

if [ ! -f "$FILE_ORIGEN" ]; then
    echo "Error: No existe el archivo $FILE_ORIGEN"
    exit 1
fi

# 2. Extraer números para base de datos y paths
ORIGEN_NUM=$(echo $ORIGEN_FULL | grep -oE '[0-9]+')
DESTINO_NUM=$(echo $DESTINO_FULL | grep -oE '[0-9]+')

# 3. Pedir datos técnicos
read -p "Nuevo Puerto APP: " PUERTO_APP
read -p "Nueva Password BBDD: " PASS_DB

echo -e "\n--- Resumen de Operación ---"
echo "Archivo:  $FILE_ORIGEN  -->  $FILE_DESTINO"
echo "ID Num:   $ORIGEN_NUM  -->  $DESTINO_NUM"
echo "Puerto:   $PUERTO_APP"
echo "----------------------------"

read -p "¿Proceder? (s/n): " CONFIRMAR

if [[ "$CONFIRMAR" =~ ^[Ss]$ ]]; then
    # Copia física del archivo
    cp "$FILE_ORIGEN" "$FILE_DESTINO"

    # A. Reemplazo del nombre completo (ej: prrepsic252 -> prrepsic261)
    sed -i "s/${ORIGEN_FULL}/${DESTINO_FULL}/g" "$FILE_DESTINO"

    # B. Reemplazo de la parte numérica (para base de datos y paths internos)
    if [ ! -z "$ORIGEN_NUM" ] && [ ! -z "$DESTINO_NUM" ]; then
        sed -i "s/${ORIGEN_NUM}/${DESTINO_NUM}/g" "$FILE_DESTINO"
    fi

    # C. Reemplazo del puerto (específicamente en la sección server)
    sed -i "/^server:/,/^[^ ]/ s/port: .*/port: ${PUERTO_APP}/" "$FILE_DESTINO"

    # D. Reemplazo de la contraseña (en la sección db)
    sed -i "/^db:/,/^[^ ]/ s/password: .*/password: ${PASS_DB}/" "$FILE_DESTINO"

    echo -e "\n✅ Archivo '$FILE_DESTINO' generado con éxito."
else
    echo -e "\n❌ Operación cancelada."
fi