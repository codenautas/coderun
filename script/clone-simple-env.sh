#!/bin/bash

# --- CONFIGURACIÓN ---
PATH_CONFIGS="/opt/insts"

echo "=== Clonador de Configuraciones YAML ==="

# 1. Identificación de archivos
read -p "Nombre de la instancia ORIGEN (ej. prrepsic252): " INSTANCIA_ORIGEN
read -p "Nombre de la instancia DESTINO (ej. prrepsic261): " INSTANCIA_DESTINO

if [[ -z "$INSTANCIA_ORIGEN" || -z "$INSTANCIA_DESTINO" ]]; then
    echo "❌ Error: Debes ingresar ambos nombres."
    return 1 2>/dev/null || exit 1
fi

FILE_ORIGEN="${PATH_CONFIGS}/${INSTANCIA_ORIGEN}.yaml"
FILE_DESTINO="${PATH_CONFIGS}/${INSTANCIA_DESTINO}.yaml"

if [ ! -f "$FILE_ORIGEN" ]; then
    echo "❌ Error: No se encuentra el archivo origen en $FILE_ORIGEN"
    return 1 2>/dev/null || exit 1
fi

# 2. Extracción de números
NUM_ORIGEN=$(echo "$INSTANCIA_ORIGEN" | grep -oP '\d+' | head -n 1 || echo "")
NUM_DESTINO=$(echo "$INSTANCIA_DESTINO" | grep -oP '\d+' | head -n 1 || echo "")

# 3. Datos de la nueva instancia
read -p "Nuevo Puerto (server: port): " NUEVO_PUERTO
read -p "Nueva Password (db: password): " NUEVA_PASS

echo -e "\n--- Resumen de Operación ---"
echo "Archivo Origen:  $FILE_ORIGEN"
echo "Archivo Destino: $FILE_DESTINO"
echo "Nuevo Puerto:    $NUEVO_PUERTO"
echo "----------------------------"

read -p "¿Generar nueva configuración? (s/n): " CONFIRMAR

if [[ "$CONFIRMAR" =~ ^[Ss]$ ]]; then
    sudo cp "$FILE_ORIGEN" "$FILE_DESTINO"
    sudo chown "$USER" "$FILE_DESTINO"

    sed -i "s|${INSTANCIA_ORIGEN}|${INSTANCIA_DESTINO}|g" "$FILE_DESTINO"

    if [ -n "$NUM_ORIGEN" ] && [ -n "$NUM_DESTINO" ]; then
        sed -i "s|${NUM_ORIGEN}|${NUM_DESTINO}|g" "$FILE_DESTINO"
    fi

    sed -i "/^server:/,/^[^ ]/ s|\(port: \).*|\1${NUEVO_PUERTO}|" "$FILE_DESTINO"
    sed -i "/^db:/,/^[^ ]/ s|\(password: \).*|\1${NUEVA_PASS}|" "$FILE_DESTINO"

    echo -e "\n✅ Archivo generado: $FILE_DESTINO"
else
    echo -e "\n❌ Operación cancelada."
fi