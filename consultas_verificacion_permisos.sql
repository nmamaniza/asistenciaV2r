-- ================================================================================
-- CONSULTAS SQL PARA VERIFICAR PERMISOS - procesarAsistencia.py
-- ================================================================================
-- Base de datos: asistenciaV2r
-- Fecha: 2025-11-27
-- ================================================================================

-- ================================================================================
-- 1. VERIFICAR TIPOS DE PERMISOS CONFIGURADOS
-- ================================================================================

SELECT 
    pt.id,
    pt.codigo,
    pt.descripcion,
    pt.permite_doble_cargo,
    pt.requiere_programacion,
    COUNT(p.id) as total_permisos_activos
FROM permissiontypes pt
LEFT JOIN permissions p ON p.permissiontype_id = pt.id AND p.estado = 1
GROUP BY pt.id, pt.codigo, pt.descripcion, pt.permite_doble_cargo, pt.requiere_programacion
ORDER BY pt.id;

-- Resultado esperado:
-- ID | CODIGO      | DESCRIPCION                  | PERMITE_DOBLE | REQUIERE_PROG | TOTAL_ACTIVOS
-- 1  | LSG         | Licencia Sin Goce de Haber   | TRUE          | FALSE         | X
-- 2  | LACTANCIA   | Licencia por Lactancia       | FALSE         | TRUE          | X
-- 3  | VACACIONES  | Vacaciones Anuales           | FALSE         | FALSE         | X
-- 4  | ENFERMEDAD  | Licencia por Enfermedad      | FALSE         | FALSE         | X
-- 5  | MATERNIDAD  | Licencia por Maternidad      | FALSE         | FALSE         | X


-- ================================================================================
-- 2. LISTAR TODOS LOS PERMISOS ACTIVOS CON SUS USUARIOS
-- ================================================================================

SELECT 
    u.dni,
    u.nombre,
    u.apellidos,
    pt.codigo as tipo_permiso,
    p.abrevia,
    p.fechaini,
    p.fechafin,
    p.descripcion,
    CASE 
        WHEN CURRENT_DATE BETWEEN p.fechaini AND p.fechafin THEN 'VIGENTE'
        WHEN CURRENT_DATE < p.fechaini THEN 'FUTURO'
        ELSE 'VENCIDO'
    END as estado_vigencia
FROM permissions p
INNER JOIN users u ON u.id = p.user_id
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
WHERE p.estado = 1
ORDER BY p.fechaini DESC, u.nombre;


-- ================================================================================
-- 3. VERIFICAR PERMISOS DE UN USUARIO ESPECÍFICO EN UNA FECHA
-- ================================================================================

-- Reemplazar @user_id y @fecha con valores reales
-- Ejemplo: @user_id = 1030, @fecha = '2025-01-20'

-- 3.1 Permisos generales (vacaciones, LSG, maternidad, enfermedad, etc.)
SELECT 
    p.id as permission_id,
    p.abrevia,
    p.descripcion,
    p.fechaini,
    p.fechafin,
    p.jobassignment_id,
    pt.id as permissiontype_id,
    pt.codigo as tipo_codigo,
    pt.descripcion as tipo_descripcion,
    CASE 
        WHEN p.jobassignment_id IS NOT NULL THEN 'Asociado a cargo específico'
        ELSE 'Aplica a todos los cargos'
    END as alcance
FROM permissions p
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
WHERE p.user_id = 1030  -- Cambiar por user_id real
AND p.estado = 1
AND '2025-01-20' BETWEEN p.fechaini AND p.fechafin  -- Cambiar por fecha real
AND pt.codigo != 'LACTANCIA'
ORDER BY pt.id;

-- 3.2 Permisos LSG asociados a un cargo específico
SELECT 
    p.id as permission_id,
    p.abrevia,
    p.jobassignment_id,
    ja.cargo,
    ja.modalidad,
    p.fechaini,
    p.fechafin,
    pt.codigo as tipo_codigo
FROM permissions p
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
INNER JOIN jobassignments ja ON ja.id = p.jobassignment_id
WHERE p.user_id = 1030  -- Cambiar por user_id real
AND p.estado = 1
AND pt.codigo = 'LSG'
AND '2025-01-20' BETWEEN p.fechaini AND p.fechafin  -- Cambiar por fecha real
ORDER BY p.fechaini;

-- 3.3 Permiso de lactancia con programación
SELECT 
    p.id as permission_id,
    p.abrevia,
    pt.id as permissiontype_id,
    pt.codigo as tipo_codigo,
    ls.modo,
    ls.minutos_diarios,
    ls.fecha_desde,
    ls.fecha_hasta
FROM permissions p
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
INNER JOIN lactation_schedules ls ON ls.permission_id = p.id
WHERE p.user_id = 1030  -- Cambiar por user_id real
AND p.estado = 1
AND pt.codigo = 'LACTANCIA'
AND '2025-01-20' BETWEEN p.fechaini AND p.fechafin  -- Cambiar por fecha real
AND '2025-01-20' BETWEEN ls.fecha_desde AND ls.fecha_hasta  -- Cambiar por fecha real
AND ls.estado = 1
LIMIT 1;

-- 3.4 Simular consulta del script Python para un cargo específico
-- Esta consulta muestra exactamente lo que obtiene el script
SELECT 
    p.id as permission_id,
    p.abrevia,
    p.jobassignment_id,
    pt.codigo as tipo_codigo,
    CASE 
        WHEN pt.codigo = 'LSG' AND p.jobassignment_id = 100 THEN 'LSG - APLICA a este cargo'
        WHEN pt.codigo = 'LSG' AND p.jobassignment_id != 100 THEN 'LSG - NO APLICA a este cargo'
        WHEN pt.codigo != 'LSG' THEN 'Otro permiso - APLICA a todos los cargos'
    END as aplicabilidad
FROM permissions p
INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
WHERE p.user_id = 3  -- Cambiar por user_id real
AND p.estado = 1
AND '2025-02-15' BETWEEN p.fechaini AND p.fechafin
AND pt.codigo != 'LACTANCIA'
AND (
    -- LSG solo aplica al cargo específico asociado al permiso
    (pt.codigo = 'LSG' AND p.jobassignment_id = 100)  -- Cambiar por jobassignment_id real
    OR
    -- Otros permisos aplican a todos los cargos
    (pt.codigo != 'LSG')
)
ORDER BY pt.id;



-- ================================================================================
-- 4. VERIFICAR ASISTENCIAS PROCESADAS CON PERMISOS
-- ================================================================================

-- 4.1 Ver asistencias con marca de VACACIONES
SELECT 
    da.fecha,
    u.dni,
    u.nombre,
    u.apellidos,
    ja.cargo,
    da.obs,
    da.final,
    cd.estado as estado_calendario,
    cd.descripcion as tipo_dia
FROM dailyattendances da
INNER JOIN jobassignments ja ON ja.id = da.jobassignment_id
INNER JOIN users u ON u.id = ja.user_id
INNER JOIN calendardays cd ON cd.fecha = da.fecha
WHERE da.obs = 'V'
AND da.estado = 1
ORDER BY da.fecha DESC, u.nombre
LIMIT 20;

-- 4.2 Ver asistencias con marca de LSG
SELECT 
    da.fecha,
    u.dni,
    u.nombre,
    u.apellidos,
    ja.cargo,
    da.obs,
    da.final,
    cd.estado as estado_calendario
FROM dailyattendances da
INNER JOIN jobassignments ja ON ja.id = da.jobassignment_id
INNER JOIN users u ON u.id = ja.user_id
INNER JOIN calendardays cd ON cd.fecha = da.fecha
WHERE da.obs LIKE '%LSG%'
AND da.estado = 1
ORDER BY da.fecha DESC, u.nombre
LIMIT 20;

-- 4.3 Ver asistencias con LACTANCIA
SELECT 
    da.fecha,
    u.dni,
    u.nombre,
    u.apellidos,
    ja.cargo,
    ws.horaini as horario_base_inicio,
    ws.horafin as horario_base_fin,
    da.horaini as hora_entrada_real,
    da.horafin as hora_salida_real,
    da.minutos_lactancia,
    da.modo_lactancia,
    da.obs,
    da.final
FROM dailyattendances da
INNER JOIN jobassignments ja ON ja.id = da.jobassignment_id
INNER JOIN users u ON u.id = ja.user_id
INNER JOIN workschedules ws ON ws.id = ja.workschedule_id
WHERE da.minutos_lactancia > 0
AND da.estado = 1
ORDER BY da.fecha DESC, u.nombre
LIMIT 20;


-- ================================================================================
-- 5. VERIFICAR USUARIOS CON MÚLTIPLES CARGOS (LSG)
-- ================================================================================

SELECT 
    u.dni,
    u.nombre,
    u.apellidos,
    COUNT(ja.id) as total_cargos,
    STRING_AGG(ja.cargo, ' | ') as cargos,
    STRING_AGG(ja.fechaini::text || ' → ' || COALESCE(ja.fechafin::text, 'Vigente'), ' | ') as periodos
FROM users u
INNER JOIN jobassignments ja ON ja.user_id = u.id
WHERE ja.estado = 1
AND (ja.fechafin IS NULL OR ja.fechafin >= CURRENT_DATE)
GROUP BY u.id, u.dni, u.nombre, u.apellidos
HAVING COUNT(ja.id) > 1
ORDER BY u.nombre;


-- ================================================================================
-- 6. VERIFICAR CALENDARIO (DÍAS LABORABLES VS NO LABORABLES)
-- ================================================================================

SELECT 
    fecha,
    estado,
    descripcion,
    CASE estado
        WHEN 0 THEN 'FERIADO'
        WHEN 1 THEN 'LABORABLE'
        WHEN 2 THEN 'RECUPERABLE'
        ELSE 'OTRO'
    END as tipo_dia
FROM calendardays
WHERE fecha BETWEEN '2025-01-01' AND '2025-01-31'
ORDER BY fecha;


-- ================================================================================
-- 7. SIMULAR PROCESAMIENTO DE ASISTENCIA PARA UN USUARIO
-- ================================================================================

-- Esta consulta simula lo que hace el script Python
WITH usuario_fecha AS (
    SELECT 
        1030 as user_id,  -- Cambiar por user_id real
        '2025-01-20'::date as fecha  -- Cambiar por fecha real
),
permisos_generales AS (
    SELECT 
        p.id,
        p.abrevia,
        pt.codigo as tipo_codigo,
        pt.id as permissiontype_id
    FROM permissions p
    INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
    CROSS JOIN usuario_fecha uf
    WHERE p.user_id = uf.user_id
    AND p.estado = 1
    AND uf.fecha BETWEEN p.fechaini AND p.fechafin
    AND pt.codigo != 'LACTANCIA'
    ORDER BY pt.id
),
lactancia AS (
    SELECT 
        p.id,
        ls.modo,
        ls.minutos_diarios
    FROM permissions p
    INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
    INNER JOIN lactation_schedules ls ON ls.permission_id = p.id
    CROSS JOIN usuario_fecha uf
    WHERE p.user_id = uf.user_id
    AND p.estado = 1
    AND pt.codigo = 'LACTANCIA'
    AND uf.fecha BETWEEN p.fechaini AND p.fechafin
    AND uf.fecha BETWEEN ls.fecha_desde AND ls.fecha_hasta
    AND ls.estado = 1
    LIMIT 1
),
calendario AS (
    SELECT estado, descripcion
    FROM calendardays
    CROSS JOIN usuario_fecha uf
    WHERE fecha = uf.fecha
)
SELECT 
    'PERMISOS GENERALES' as tipo,
    COUNT(*) as cantidad,
    STRING_AGG(tipo_codigo || ' (' || abrevia || ')', ', ') as detalle
FROM permisos_generales
UNION ALL
SELECT 
    'LACTANCIA' as tipo,
    COUNT(*) as cantidad,
    STRING_AGG(modo || ' - ' || minutos_diarios || ' min', ', ') as detalle
FROM lactancia
UNION ALL
SELECT 
    'CALENDARIO' as tipo,
    estado as cantidad,
    descripcion as detalle
FROM calendario;


-- ================================================================================
-- 8. INSERTAR PERMISOS DE PRUEBA (OPCIONAL)
-- ================================================================================

-- IMPORTANTE: Solo ejecutar si necesitas crear permisos de prueba
-- Reemplazar los IDs y fechas según tu caso

/*
-- Ejemplo: Insertar permiso de VACACIONES
INSERT INTO permissions (
    abrevia, descripcion, fechaini, fechafin, 
    estado, user_id, permissiontype_id, usercrea
) VALUES (
    'VAC', 'Vacaciones anuales', '2025-02-01', '2025-02-15',
    1, 1030, 3, 1
);

-- Ejemplo: Insertar permiso de ENFERMEDAD
INSERT INTO permissions (
    abrevia, descripcion, fechaini, fechafin, 
    estado, user_id, permissiontype_id, usercrea
) VALUES (
    'ENF', 'Licencia por enfermedad', '2025-03-01', '2025-03-05',
    1, 1030, 4, 1
);

-- Ejemplo: Insertar permiso de LSG
INSERT INTO permissions (
    abrevia, descripcion, fechaini, fechafin, 
    estado, user_id, permissiontype_id, usercrea
) VALUES (
    'LSG', 'Licencia sin goce para segundo empleo', '2025-04-01', '2025-12-31',
    1, 1030, 1, 1
);
*/


-- ================================================================================
-- 9. LIMPIAR ASISTENCIAS PROCESADAS (PARA REPROCESAR)
-- ================================================================================

-- IMPORTANTE: Solo ejecutar si necesitas reprocesar asistencias
-- Esto eliminará los registros de dailyattendances para las fechas especificadas

/*
DELETE FROM dailyattendances
WHERE fecha BETWEEN '2025-01-01' AND '2025-01-31'
AND jobassignment_id IN (
    SELECT id FROM jobassignments WHERE user_id = 1030  -- Cambiar por user_id real
);
*/


-- ================================================================================
-- FIN DE CONSULTAS
-- ================================================================================
