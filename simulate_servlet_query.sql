-- Script para simular exactamente lo que hace ConsolidatedDataUserServlet
-- Esto nos ayudará a entender por qué no se muestran los datos

-- PASO 1: Verificar el user_id del usuario autenticado (DNI 10333768)
SELECT id, dni, nombre, apellidos, email, estado
FROM users
WHERE dni = '10333768' AND estado = 1;

-- PASO 2: Simular la consulta exacta del servlet
-- Reemplaza USER_ID con el id obtenido en el paso 1 (debería ser 255)

SELECT 
    u.dni, 
    COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre,
    ja.modalidad, 
    da.fecha, 
    da.final
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE da.estado = 1 
AND u.id = 255  -- <-- REEMPLAZA con el user_id correcto
AND da.fecha >= '2025-11-01' 
AND da.fecha <= '2025-11-30'
ORDER BY da.fecha ASC;

-- PASO 3: Ver qué jobassignments tiene el usuario
SELECT 
    ja.id,
    ja.modalidad,
    ja.cargo,
    ja.fechaini,
    ja.fechafin,
    ja.estado,
    ja.user_id
FROM jobassignments ja
WHERE ja.user_id = 255  -- <-- REEMPLAZA con el user_id correcto
AND ja.estado = 1;

-- PASO 4: Ver si hay registros de asistencia para CUALQUIER jobassignment del usuario
SELECT 
    da.id,
    da.fecha,
    da.final,
    da.estado,
    da.jobassignment_id,
    ja.modalidad,
    ja.user_id
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
WHERE ja.user_id = 255  -- <-- REEMPLAZA con el user_id correcto
AND da.fecha BETWEEN '2025-11-01' AND '2025-11-30'
AND da.estado = 1
ORDER BY da.fecha;
