# Mejoras en procesarAsistencia.py - Gestión de Permisos

## Fecha: 2025-11-27
## Autor: Sistema AsistenciaV2r

---

## RESUMEN DE CAMBIOS

El archivo `procesarAsistencia.py` ha sido mejorado para manejar correctamente todos los tipos de permisos de la tabla `permissions`, respetando las fechas de inicio y fin (`permissions.fechaini` y `permissions.fechafin`).

---

## TIPOS DE PERMISOS IMPLEMENTADOS

### 1. VACACIONES (permissiontype_id=3)
- **Código**: `VACACIONES`
- **Comportamiento**: Afecta a TODOS los días, independientemente del estado del calendario (0=feriado, 1=laborable, 2=recuperable, 3=otros)
- **Marca en asistencia**: Se coloca "V" en los campos `obs` y `final` de `dailyattendances`
- **Prioridad**: MÁXIMA (se evalúa primero)

### 2. LACTANCIA (permissiontype_id=2)
- **Código**: `LACTANCIA`
- **Comportamiento**: NO afecta los días, solo modifica el horario de trabajo
  - **Modo INICIO**: La hora de ingreso se ajusta sumando los minutos de lactancia a `workschedules.horaini`
  - **Modo FIN**: La hora de salida se ajusta restando los minutos de lactancia a `workschedules.horafin`
- **Marca en asistencia**: No modifica `obs` ni `final`, solo ajusta el cálculo de tardanzas y horas extras
- **Nota**: Esta funcionalidad ya estaba implementada correctamente, NO se modificó

### 3. OTROS PERMISOS (permissiontype_id=4,5,6,...)
- **Códigos**: `ENFERMEDAD`, `MATERNIDAD`, licencias con goce (LCG), etc.
- **Comportamiento**: Afecta SOLO a días laborables (`calendardays.estado=1`)
- **Marca en asistencia**: Se coloca la abreviatura del permiso (`permissions.abrevia`) en los campos `obs` y `final`
- **Ejemplos**:
  - Enfermedad: "ENF"
  - Maternidad: "MAT"
  - Licencia con goce: "LCG"

### 4. LICENCIA SIN GOCE - LSG (permissiontype_id=1)
- **Código**: `LSG`
- **Comportamiento**: Funciona igual que los "otros permisos" (punto 3)
  - Afecta SOLO a días laborables (`calendardays.estado=1`)
  - Se coloca la abreviatura en `obs` y `final`
- **Característica especial**: Permite que el usuario tenga un nuevo cargo simultáneo
- **IMPORTANTE**: El permiso LSG está asociado a un **cargo específico** (`permissions.jobassignment_id`)
  - Si un usuario tiene 2 cargos, el LSG solo se aplica al cargo indicado en el permiso
  - El otro cargo se procesa normalmente sin marca de LSG
  - Ejemplo:
    - Cargo 1 (ID=100): Contador → Tiene LSG → Marca "LSG" en asistencia
    - Cargo 2 (ID=101): Consultor → Sin LSG → Se procesa normalmente (A, F, tardanzas, etc.)
- **Nota**: La validación de cargos simultáneos se maneja en el backend Java, no en este script

---

## ORDEN DE EVALUACIÓN DE PERMISOS

El script evalúa los permisos en el siguiente orden de prioridad:

1. **VACACIONES** → Si existe, marca "V" y termina el procesamiento
2. **LSG** → Si existe y es día laborable, marca la abreviatura y termina
3. **OTROS PERMISOS** → Si existen y es día laborable, marca la abreviatura y termina
4. **LACTANCIA** → No termina el procesamiento, solo ajusta horarios
5. **ASISTENCIA NORMAL** → Si no hay permisos, procesa marcaciones normalmente

---

## FUNCIONES MODIFICADAS

### 1. `obtener_permisos_activos(conn, user_id, fecha, jobassignment_id, cargo_fechaini, cargo_fechafin)`
**Antes**: `obtener_permisos_lactancia(conn, user_id, fecha)`

**Cambios**:
- Ahora obtiene TODOS los permisos activos del usuario en la fecha especificada
- Recibe el parámetro `jobassignment_id` para filtrar LSG por cargo específico
- Recibe `cargo_fechaini` y `cargo_fechafin` para validar que los permisos estén dentro del rango del cargo
- Retorna un diccionario con dos claves:
  - `permisos_generales`: Lista de permisos (vacaciones, LSG, maternidad, etc.)
  - `lactancia`: Permiso de lactancia con su programación (si existe)

**Lógica de filtrado**:
- **LSG**: Solo se incluye si `permissions.jobassignment_id = jobassignment_id` (cargo específico)
- **Otros permisos** (VACACIONES, ENFERMEDAD, MATERNIDAD, etc.): Se incluyen para todos los cargos del usuario

**Validaciones de fechas** ⭐ NUEVO:
- `permissions.fechaini >= cargo_fechaini` (el permiso no puede iniciar antes del cargo)
- Si `cargo_fechafin IS NOT NULL`: `permissions.fechafin <= cargo_fechafin` (el permiso no puede terminar después del cargo)
- Si `cargo_fechafin IS NULL`: No hay restricción de fecha fin

**Query SQL**:
```sql
-- Permisos generales
SELECT p.id, p.abrevia, p.fechaini, p.fechafin, pt.id, pt.codigo, pt.descripcion
FROM permissions p
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
WHERE p.user_id = %s
  AND p.estado = 1
  AND %s BETWEEN p.fechaini AND p.fechafin
  AND pt.codigo != 'LACTANCIA'
ORDER BY pt.id

-- Lactancia
SELECT p.id, p.abrevia, pt.id, pt.codigo, ls.modo, ls.minutos_diarios
FROM permissions p
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
INNER JOIN lactation_schedules ls ON ls.permission_id = p.id
WHERE p.user_id = %s
  AND p.estado = 1
  AND pt.codigo = 'LACTANCIA'
  AND %s BETWEEN p.fechaini AND p.fechafin
  AND %s BETWEEN ls.fecha_desde AND ls.fecha_hasta
  AND ls.estado = 1
```

### 2. `calcular_asistencia(horario, marcaciones, permisos, estado_calendario)`
**Antes**: `calcular_asistencia(horario, marcaciones, lactancia, estado_calendario)`

**Cambios**:
- Ahora recibe el diccionario completo de `permisos` en lugar de solo `lactancia`
- Implementa la lógica de evaluación de permisos en orden de prioridad
- Respeta el estado del calendario para cada tipo de permiso

**Lógica implementada**:
```python
# 1. Verificar VACACIONES (afecta todos los días)
if permiso_vacaciones:
    resultado['obs'] = 'V'
    resultado['final'] = 'V'
    return resultado

# 2. Verificar LSG (solo días laborables)
if permiso_lsg and estado_calendario == 1:
    resultado['obs'] = abrevia
    resultado['final'] = abrevia
    return resultado

# 3. Verificar OTROS PERMISOS (solo días laborables)
if otros_permisos and estado_calendario == 1:
    resultado['obs'] = abrevia
    resultado['final'] = abrevia
    return resultado

# 4. LACTANCIA (no afecta obs/final, solo horarios)
# Continúa con procesamiento normal...
```

### 3. `procesar_fecha(conn, fecha, dni=None)`

**Cambios**:
- Actualizada la llamada de `obtener_permisos_lactancia()` a `obtener_permisos_activos()`
- Pasa el diccionario completo de permisos a `calcular_asistencia()`

---

## EJEMPLOS DE USO

### Ejemplo 1: Usuario con vacaciones
```bash
# Usuario con permiso de vacaciones del 2025-01-15 al 2025-01-20
python procesarAsistencia.py --fecha-inicio 2025-01-15 --fecha-fin 2025-01-20 --dni 12345678

# Resultado en dailyattendances:
# - obs = 'V'
# - final = 'V'
# - Para TODOS los días (laborables, feriados, recuperables)
```

### Ejemplo 2: Usuario con licencia por enfermedad
```bash
# Usuario con permiso de enfermedad (abrevia='ENF') del 2025-02-01 al 2025-02-05
python procesarAsistencia.py --fecha-inicio 2025-02-01 --fecha-fin 2025-02-05 --dni 87654321

# Resultado en dailyattendances:
# - obs = 'ENF'
# - final = 'ENF'
# - Solo para días LABORABLES (estado=1)
# - Fines de semana no se marcan
```

### Ejemplo 3: Usuario con LSG y nuevo cargo
```bash
# Usuario con LSG del 2025-03-01 al 2025-06-30
python procesarAsistencia.py --fecha-inicio 2025-03-01 --fecha-fin 2025-03-31 --dni 11223344

# Resultado en dailyattendances:
# - obs = 'LSG' (o la abreviatura definida)
# - final = 'LSG'
# - Solo para días LABORABLES
# - El usuario puede tener dos cargos simultáneos
```

### Ejemplo 4: Usuario con lactancia
```bash
# Usuario con lactancia modo INICIO (60 minutos) del 2025-01-15 al 2025-12-31
python procesarAsistencia.py --fecha-inicio 2025-01-15 --fecha-fin 2025-01-20 --dni 41567460

# Resultado en dailyattendances:
# - obs y final se calculan normalmente (A, F, tardanzas, etc.)
# - horaini esperada se ajusta: 08:00 → 09:00
# - minutos_lactancia = 60
# - modo_lactancia = 'INICIO'
```

---

## VALIDACIONES IMPLEMENTADAS

### 1. **Respeto de fechas del permiso**
- Solo se aplican permisos si la fecha procesada está entre `permissions.fechaini` y `permissions.fechafin`
- Condición SQL: `fecha BETWEEN p.fechaini AND p.fechafin`

### 2. **Estado del permiso**
- Solo se consideran permisos con `permissions.estado = 1` (aprobados)

### 3. **Estado del calendario**
- LSG y otros permisos solo afectan días laborables (`calendardays.estado = 1`)
- VACACIONES afecta todos los días (estado 0, 1, 2, 3)

### 4. **Programación de lactancia**
- Se valida que la fecha esté dentro del rango `lactation_schedules.fecha_desde` y `lactation_schedules.fecha_hasta`

### 5. **Validación de rango del cargo** ⭐ NUEVO
- El permiso debe iniciar después o en la fecha de inicio del cargo
- Condición SQL: `p.fechaini >= ja.fechaini`
- Evita permisos que inicien antes del cargo

### 6. **Validación de fecha fin del cargo** ⭐ NUEVO
- Si el cargo tiene `fechafin`, el permiso debe tener `fechafin <= cargo.fechafin`
- Condición SQL: `(ja.fechafin IS NULL) OR (p.fechafin <= ja.fechafin)`
- Evita permisos que se extiendan más allá del cargo
- Ejemplo:
  - Cargo: 2025-01-01 → 2025-06-30
  - Permiso válido: 2025-02-01 → 2025-05-31 ✓
  - Permiso inválido: 2025-02-01 → 2025-07-31 ✗ (se extiende más allá del cargo)

### 7. **Filtrado de LSG por cargo específico**
- LSG solo se aplica al cargo asociado en `permissions.jobassignment_id`
- Otros permisos (VACACIONES, ENFERMEDAD, etc.) aplican a todos los cargos del usuario

---

## COMPATIBILIDAD

- **Base de datos**: PostgreSQL (asistenciaV2r)
- **Python**: 3.x
- **Dependencias**: psycopg2
- **Esquema**: asistenciaV3vc_mejorado.sql

---

## NOTAS IMPORTANTES

1. La lactancia NO se toca porque ya está funcionando correctamente
2. Los permisos se evalúan en orden de prioridad (vacaciones > LSG > otros > lactancia)
3. Si un usuario tiene múltiples permisos activos en la misma fecha, se aplica el de mayor prioridad
4. La validación de cargos simultáneos con LSG se maneja en el backend Java, no en este script
5. Las abreviaturas se toman del campo `permissions.abrevia`, con fallback al código del tipo de permiso

---

## TESTING RECOMENDADO

1. Probar con usuario que tiene vacaciones en días laborables y feriados
2. Probar con usuario que tiene LSG solo en días laborables
3. Probar con usuario que tiene enfermedad/maternidad
4. Probar con usuario que tiene lactancia (verificar que no se rompa)
5. Probar con usuario que tiene múltiples permisos simultáneos
6. Probar con usuario sin permisos (asistencia normal)

---

## CONTACTO

Para consultas o reportar problemas:
- Base de datos: asistenciaV2r @ 172.16.1.61
- Usuario: nestor
- Sistema: AsistenciaV2r
