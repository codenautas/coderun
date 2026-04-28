#!/bin/bash

# --- CONFIGURACIÓN ---
# Usamos path absoluto solo para la base, el resto es simple
PATH_CONFIGS="/opt/insts"

echo "=== Clonador de Configuraciones YAML ==="

# 1. Identificación de archivos
read -p "Nombre de la instancia ORIGEN (ej. prrepsic252): " INSTANCIA_ORIGEN
read -p "Nombre de la instancia DESTINO (ej. prrepsic261): " INSTANCIA_DESTINO

# Validación simple para no cerrar la consola si falta un dato
if [[ -z "$INSTANCIA_ORIGEN" || -z "$INSTANCIA_DESTINO" ]]; then
    echo "❌ Error: Debes ingresar ambos nombres."
    return 1 2>/dev/null || exit 1
fi

FILE_ORIGEN="${PATH_CONFIGS}/${INSTANCIA_ORIGEN}.yaml"
FILE_DESTINO="${PATH_CONFIGS}/${INSTANCIA_DESTINO}.yaml"

if [ ! -f "$FILE_ORIGEN" ]; then
    echo "❌ Error: No existe el archivo $FILE_ORIGEN"
    return 1 2>/dev/null || exit 1
fi

# 2. Extracción de números (para bases de datos, etc)
NUM_ORIGEN=$(echo "$INSTANCIA_ORIGEN" | grep -oP '\d+' | head -n 1 || echo "")
NUM_DESTINO=$(echo "$INSTANCIA_DESTINO" | grep -oP '\d+' | head -n 1 || echo "")

# 3. Datos nuevos
read -p "Nuevo Puerto: " NUEVO_PUERTO
read -p "Nueva Password BBDD: " NUEVA_PASS

echo -e "\n--- Resumen ---"
echo "Origen: $INSTANCIA_ORIGEN -> Destino: $INSTANCIA_DESTINO"
echo "Puerto: $NUEVO_PUERTO"

read -p "¿Proceder? (s/n): " CONFIRMAR

if [[ "$CONFIRMAR" =~ ^[Ss]$ ]]; then
    # Copia y permisos
    sudo cp "$FILE_ORIGEN" "$FILE_DESTINO"
    sudo chown "$USER" "$FILE_DESTINO"

    # Reemplazos
    # Reemplazo del nombre completo
    sed -i "s|${INSTANCIA_ORIGEN}|${INSTANCIA_DESTINO}|g" "$FILE_DESTINO"

    # Reemplazo de los números (si existen)
    if [ -n "$NUM_ORIGEN" ] && [ -n "$NUM_DESTINO" ]; then
        sed -i "s|${NUM_ORIGEN}|${NUM_DESTINO}|g" "$FILE_DESTINO"
    fi

    # Reemplazo específico de puerto y password
    sed -i "/^server:/,/^[^ ]/ s|\(port: \).*|\1${NUEVO_PUERTO}|" "$FILE_DESTINO"
    sed -i "/^db:/,/^[^ ]/ s|\(password: \).*|\1${NUEVA_PASS}|" "$FILE_DESTINO"

    echo -e "\n✅ Listo: $FILE_DESTINO generado."
else
    echo -e "\n❌ Operación cancelada."
fi