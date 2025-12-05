-- Script para verificar datos de asistencia del usuario 10333768
-- Ejecutar en PostgreSQL

-- 1. Verificar que el usuario existe
SELECT id, dni, nombre, apellidos, email, estado 
FROM users 
WHERE dni = '10333768';

-- 2. Verificar asignaciones de trabajo (jobassignments) del usuario
SELECT ja.id, ja.modalidad, ja.cargo, ja.fechaini, ja.fechafin, ja.estado, ja.user_id
FROM jobassignments ja
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768';

-- 3. Verificar registros de asistencia diaria para noviembre 2025
SELECT da.id, da.fecha, da.horaini, da.horafin, da.final, da.obs, da.estado, da.jobassignment_id
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768'
AND da.fecha BETWEEN '2025-11-01' AND '2025-11-30'
ORDER BY da.fecha;

-- 4. Verificar específicamente los días 3, 4, 5 de noviembre 2025
SELECT da.id, da.fecha, da.horaini, da.horafin, da.final, da.obs, da.doc, da.estado
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768'
AND da.fecha IN ('2025-11-03', '2025-11-04', '2025-11-05')
ORDER BY da.fecha;

-- 5. Si los registros existen, verificar el formato del campo 'final'
SELECT da.fecha, 
       da.final,
       LENGTH(da.final) as longitud_final,
       da.estado,
       ja.id as job_id,
       u.id as user_id
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768'
AND da.fecha BETWEEN '2025-11-03' AND '2025-11-05';
