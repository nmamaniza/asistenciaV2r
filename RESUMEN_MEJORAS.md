# RESUMEN DE MEJORAS - procesarAsistencia.py

## 📋 CAMBIOS REALIZADOS

### ✅ Función: `obtener_permisos_activos()`
**Antes**: `obtener_permisos_lactancia()` - Solo obtenía lactancia
**Ahora**: Obtiene TODOS los permisos activos del usuario

```python
return {
    'permisos_generales': [vacaciones, LSG, maternidad, enfermedad, ...],
    'lactancia': {modo, minutos_diarios, ...}
}
```

### ✅ Función: `calcular_asistencia()`
**Mejora**: Implementa lógica de prioridad de permisos

```
PRIORIDAD 1: VACACIONES → "V" en todos los días
PRIORIDAD 2: LSG → Abreviatura solo en días laborables
PRIORIDAD 3: OTROS → Abreviatura solo en días laborables
PRIORIDAD 4: LACTANCIA → Ajusta horarios, no modifica obs/final
```

---

## 🎯 REGLAS DE NEGOCIO IMPLEMENTADAS

### 1️⃣ VACACIONES (ID=3)
```
Código: VACACIONES
Afecta: TODOS los días (estado 0,1,2,3)
Marca: "V" en obs y final
Ejemplo: Usuario de vacaciones → V V V V V (todos los días)
```

### 2️⃣ LACTANCIA (ID=2)
```
Código: LACTANCIA
Afecta: Solo horarios, NO los días
Modos:
  - INICIO: horaini + minutos_lactancia
  - FIN: horafin - minutos_lactancia
Marca: No modifica obs/final
Ejemplo: Horario 8:00-16:45 + Lactancia INICIO 60min → 9:00-16:45
```

### 3️⃣ OTROS PERMISOS (ID=4,5,6,...)
```
Códigos: ENFERMEDAD, MATERNIDAD, LCG, etc.
Afecta: Solo días LABORABLES (estado=1)
Marca: Abreviatura en obs y final
Ejemplo: Enfermedad (ENF) → ENF solo en días laborables
```

### 4️⃣ LSG (ID=1)
```
Código: LSG
Afecta: Solo días LABORABLES (estado=1)
Marca: Abreviatura en obs y final
Especial: Permite nuevo cargo simultáneo
Ejemplo: LSG → LSG solo en días laborables
```

---

## 📊 TABLA DE COMPORTAMIENTO

| Tipo Permiso | Días Afectados | Marca en obs/final | Permite 2 Cargos |
|--------------|----------------|-------------------|------------------|
| VACACIONES   | Todos (0,1,2,3)| V                 | No               |
| LACTANCIA    | Ninguno*       | No modifica       | No               |
| LSG          | Laborables (1) | Abreviatura       | **Sí**           |
| ENFERMEDAD   | Laborables (1) | Abreviatura       | No               |
| MATERNIDAD   | Laborables (1) | Abreviatura       | No               |
| OTROS        | Laborables (1) | Abreviatura       | No               |

*Lactancia solo modifica horarios, no marca días

---

## 🔍 EJEMPLOS DE PROCESAMIENTO

### Ejemplo 1: Usuario con VACACIONES
```
Fecha: 2025-01-15 (Lunes - Laborable)
Permiso: VACACIONES del 2025-01-15 al 2025-01-20
Resultado:
  ✓ obs = "V"
  ✓ final = "V"
  ✓ Se ignoran marcaciones
```

### Ejemplo 2: Usuario con ENFERMEDAD
```
Fecha: 2025-02-01 (Sábado - Feriado)
Permiso: ENFERMEDAD (ENF) del 2025-01-30 al 2025-02-05
Resultado:
  ✓ obs = "" (no se marca porque es feriado)
  ✓ final = ""
  ✓ Solo se marca en días laborables
```

### Ejemplo 3: Usuario con LACTANCIA
```
Fecha: 2025-03-10 (Lunes - Laborable)
Permiso: LACTANCIA INICIO 60min del 2025-01-15 al 2025-12-31
Horario: 08:00 - 16:45
Marcaciones: 09:05 (INGRESO), 17:00 (SALIDA)
Resultado:
  ✓ horaini esperada: 09:00 (8:00 + 60min)
  ✓ Llegó a las 09:05 → 5 minutos tarde (dentro de tolerancia)
  ✓ obs = "5" o "A" (según tolerancia)
  ✓ minutos_lactancia = 60
  ✓ modo_lactancia = "INICIO"
```

### Ejemplo 4: Usuario con LSG y nuevo cargo
```
Fecha: 2025-04-15 (Martes - Laborable)
Permiso: LSG del 2025-04-01 al 2025-06-30
Cargo 1: Contador (con LSG)
Cargo 2: Consultor Externo (permitido por LSG)
Resultado:
  ✓ Cargo 1: obs = "LSG", final = "LSG"
  ✓ Cargo 2: Se procesa normalmente
```

---

## 🧪 COMANDOS DE PRUEBA

### Probar script de verificación
```bash
python test_permisos.py
```

### Procesar fecha específica
```bash
python procesarAsistencia.py --fecha-inicio 2025-01-15 --fecha-fin 2025-01-20
```

### Procesar usuario específico
```bash
python procesarAsistencia.py --fecha-inicio 2025-01-15 --fecha-fin 2025-01-20 --dni 41567460
```

### Procesar ayer (por defecto)
```bash
python procesarAsistencia.py
```

---

## ⚠️ NOTAS IMPORTANTES

1. **Lactancia NO se modificó** - Ya funcionaba correctamente
2. **Fechas se respetan** - Solo aplica permisos entre fechaini y fechafin
3. **Estado del permiso** - Solo permisos con estado=1 (aprobados)
4. **Prioridad de permisos** - Si hay múltiples permisos, se aplica el de mayor prioridad
5. **Validación de cargos** - La validación de LSG con 2 cargos está en el backend Java

---

## 📝 ARCHIVOS MODIFICADOS

- ✅ `procesarAsistencia.py` - Script principal mejorado
- ✅ `MEJORAS_PROCESAMIENTO_PERMISOS.md` - Documentación completa
- ✅ `test_permisos.py` - Script de prueba
- ✅ `RESUMEN_MEJORAS.md` - Este archivo

---

## 🎉 LISTO PARA USAR

El script está listo para procesar asistencias con todos los tipos de permisos correctamente implementados.
