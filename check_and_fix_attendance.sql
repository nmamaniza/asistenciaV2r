-- Verificar registros de asistencia existentes para el usuario 10333768 en noviembre 2025

-- 1. Ver TODOS los registros de asistencia (incluyendo estado = 0)
SELECT 
    da.id,
    da.fecha,
    da.horaini,
    da.horafin,
    da.final,
    da.obs,
    da.doc,
    da.estado,
    da.jobassignment_id
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768'
AND da.fecha BETWEEN '2025-11-01' AND '2025-11-30'
ORDER BY da.fecha;

-- 2. Ver específicamente los días 3, 4, 5 de noviembre
SELECT 
    da.id,
    da.fecha,
    da.horaini,
    da.horafin,
    da.final,
    da.obs,
    da.doc,
    da.estado,
    da.jobassignment_id,
    ja.id as job_id,
    ja.modalidad
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768'
AND da.fecha IN ('2025-11-03', '2025-11-04', '2025-11-05')
ORDER BY da.fecha;

-- 3. Si los registros existen pero están con estado = 0, activarlos
UPDATE dailyattendances
SET estado = 1,
    final = COALESCE(NULLIF(final, ''), 'A'),
    updated_at = CURRENT_TIMESTAMP
WHERE id IN (
    SELECT da.id
    FROM dailyattendances da
    JOIN jobassignments ja ON ja.id = da.jobassignment_id
    JOIN users u ON u.id = ja.user_id
    WHERE u.dni = '10333768'
    AND da.fecha IN ('2025-11-03', '2025-11-04', '2025-11-05')
    AND da.estado = 0
);

-- 4. Verificar después de la actualización
SELECT 
    da.id,
    da.fecha,
    da.horaini,
    da.horafin,
    da.final,
    da.estado,
    da.jobassignment_id
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
WHERE u.dni = '10333768'
AND da.fecha IN ('2025-11-03', '2025-11-04', '2025-11-05')
ORDER BY da.fecha;
