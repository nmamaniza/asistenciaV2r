-- =========================================================
--  BASE DE DATOS ASISTENCIAV3VC - ESQUEMA MEJORADO
--  Sistema de Asistencia para Institución Pública
--  Autor: Sistema AsistenciaV3VC
--  Fecha: 2025
--  
--  MEJORAS IMPLEMENTADAS:
--  ✓ LSG permite dos cargos simultáneos
--  ✓ Lactancia con programación flexible (inicio/fin de jornada)
--  ✓ Tolerancia 15 min con recuperación automática
--  ✓ Campos de auditoría en todas las tablas
--  ✓ Calendario completo 2025
--  ✓ Datos de prueba completos
-- =========================================================

-- Crear base de datos
-- CREATE DATABASE asistenciaV3vc;
-- \c asistenciaV3vc;

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================================================
--  TIPOS PERSONALIZADOS
-- =========================================================

DO $$
BEGIN
  -- Modo de lactancia
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lactancia_mode') THEN
    CREATE TYPE lactancia_mode AS ENUM ('INICIO','FIN');
  END IF;
  
  -- Tipo de día en calendario
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_dia') THEN
    CREATE TYPE tipo_dia AS ENUM ('FERIADO','LABORABLE','RECUPERABLE');
  END IF;
  
  -- Tipo de marcaje
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_marcaje') THEN
    CREATE TYPE tipo_marcaje AS ENUM ('INGRESO','SALIDA','INTERMEDIO');
  END IF;
  
  -- Estado general
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_general') THEN
    CREATE TYPE estado_general AS ENUM ('ACTIVO','INACTIVO','SUSPENDIDO');
  END IF;
END$$;

-- =========================================================
--  FUNCIÓN PARA TRIGGERS DE AUDITORÍA
-- =========================================================
CREATE OR REPLACE FUNCTION actualizar_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
--  TABLA: USERS (USUARIOS DEL SISTEMA)
-- =========================================================
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    dni VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    apellidos VARCHAR(200),
    telefono VARCHAR(20),
    direccion TEXT,
    fecha_nacimiento DATE,
    genero CHAR(1) CHECK (genero IN ('M','F')),
    role VARCHAR(50) DEFAULT 'usuario',
    estado SMALLINT DEFAULT 1 CHECK (estado IN (0,1)),
    ultimo_acceso TIMESTAMPTZ,
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    send_email CHAR(1) CHECK (send_email IN ('Y', 'N')) DEFAULT 'N'
);

-- Trigger para updated_at
CREATE TRIGGER trg_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

-- Índices
CREATE INDEX idx_users_dni ON users(dni);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_estado ON users(estado);

-- =========================================================
--  TABLA: WORKSCHEDULES (HORARIOS DE TRABAJO)
-- =========================================================
DROP TABLE IF EXISTS workschedules CASCADE;
CREATE TABLE workschedules (
    id SERIAL PRIMARY KEY,
    descripcion VARCHAR(200) NOT NULL,
    horaini TIME NOT NULL,
    horafin TIME NOT NULL,
    horatarde TIME, -- Hora de inicio de turno tarde o break
    tolerancia_min SMALLINT DEFAULT 15, -- Tolerancia en minutos
    horas_jornada DECIMAL(4,2) DEFAULT 8.0,
    estado SMALLINT DEFAULT 1 CHECK (estado IN (0,1)),
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER trg_workschedules_updated_at 
    BEFORE UPDATE ON workschedules 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

-- =========================================================
--  TABLA: JOBASSIGNMENTS (ASIGNACIONES DE TRABAJO/CARGOS)
-- =========================================================
DROP TABLE IF EXISTS jobassignments CASCADE;
CREATE TABLE jobassignments (
    id SERIAL PRIMARY KEY,
    modalidad VARCHAR(100), -- CAS, CAP, NOMBRADO, etc.
    cargo VARCHAR(200),
    area VARCHAR(200),
    equipo VARCHAR(200),
    jefe VARCHAR(200),
    fechaini DATE NOT NULL,
    fechafin DATE, -- NULL = vigente
    salario DECIMAL(10,2),
    observaciones TEXT,
    estado SMALLINT DEFAULT 1 CHECK (estado IN (0,1)),
    user_id INT NOT NULL REFERENCES users(id),
    workschedule_id INT NOT NULL REFERENCES workschedules(id),
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraint: fechafin debe ser mayor o igual a fechaini
    CONSTRAINT chk_fechas_validas CHECK (fechafin IS NULL OR fechafin >= fechaini)
);

CREATE TRIGGER trg_jobassignments_updated_at 
    BEFORE UPDATE ON jobassignments 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

-- Índices importantes
CREATE INDEX idx_jobassignments_user ON jobassignments(user_id);
CREATE INDEX idx_jobassignments_fechas ON jobassignments(fechaini, fechafin);
CREATE INDEX idx_jobassignments_activos ON jobassignments(user_id, estado) WHERE estado = 1;

-- =========================================================
--  TABLA: PERMISSIONTYPES (TIPOS DE PERMISOS)
-- =========================================================
DROP TABLE IF EXISTS permissiontypes CASCADE;
CREATE TABLE permissiontypes (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(20) UNIQUE NOT NULL,
    descripcion VARCHAR(200) NOT NULL,
    permite_doble_cargo BOOLEAN DEFAULT FALSE, -- TRUE para LSG
    requiere_programacion BOOLEAN DEFAULT FALSE, -- TRUE para LACTANCIA
    minutos_diarios_default INT, -- 60 para lactancia
    dias_maximo INT, -- 365 para lactancia
    estado SMALLINT DEFAULT 1,
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER trg_permissiontypes_updated_at 
    BEFORE UPDATE ON permissiontypes 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

-- =========================================================
--  TABLA: PERMISSIONS (PERMISOS/LICENCIAS)
-- =========================================================
DROP TABLE IF EXISTS permissions CASCADE;
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    abrevia VARCHAR(10),
    descripcion TEXT,
    fechaini DATE NOT NULL,
    fechafin DATE NOT NULL,
    motivo TEXT,
    documento_adjunto VARCHAR(500),
    aprobado_por INT REFERENCES users(id),
    fecha_aprobacion TIMESTAMPTZ,
    estado SMALLINT DEFAULT 0, -- 0=pendiente, 1=aprobado, 2=rechazado
    jobassignment_id INT REFERENCES jobassignments(id),
    user_id INT REFERENCES users(id),
    permissiontype_id INT REFERENCES permissiontypes(id),
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_fechas_permiso CHECK (fechafin >= fechaini)
);

CREATE TRIGGER trg_permissions_updated_at 
    BEFORE UPDATE ON permissions 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

CREATE INDEX idx_permissions_user_fechas ON permissions(user_id, fechaini, fechafin);
CREATE INDEX idx_permissions_job_fechas ON permissions(jobassignment_id, fechaini, fechafin);
CREATE INDEX idx_permissions_tipo ON permissions(permissiontype_id);

-- =========================================================
--  TABLA: LACTATION_SCHEDULES (PROGRAMACIÓN DE LACTANCIA)
-- =========================================================
DROP TABLE IF EXISTS lactation_schedules CASCADE;
CREATE TABLE lactation_schedules (
    id SERIAL PRIMARY KEY,
    permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    fecha_desde DATE NOT NULL,
    fecha_hasta DATE NOT NULL,
    modo lactancia_mode NOT NULL, -- 'INICIO' o 'FIN'
    minutos_diarios INT DEFAULT 60,
    observaciones TEXT,
    estado SMALLINT DEFAULT 1,
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_fechas_lactancia CHECK (fecha_hasta >= fecha_desde)
);

CREATE TRIGGER trg_lactation_schedules_updated_at 
    BEFORE UPDATE ON lactation_schedules 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

-- Evitar solapamiento real de programaciones para el mismo permiso
-- Permite programaciones consecutivas (ej: 2025-01-01 a 2025-01-31 y 2025-02-01 a 2025-02-28)
CREATE OR REPLACE FUNCTION check_lactation_overlap()
RETURNS TRIGGER AS $$
BEGIN
    -- Verificar si existe solapamiento real (no consecutivo)
    IF EXISTS (
        SELECT 1 FROM lactation_schedules ls
        WHERE ls.permission_id = NEW.permission_id
        AND ls.id != COALESCE(NEW.id, -1)
        AND ls.estado = 1
        AND (
            -- Solapamiento: nueva programación empieza antes de que termine otra
            (NEW.fecha_desde <= ls.fecha_hasta AND NEW.fecha_hasta >= ls.fecha_desde)
        )
    ) THEN
        RAISE EXCEPTION 'Existe solapamiento en las fechas de programación de lactancia para el permiso %', NEW.permission_id
        USING ERRCODE = 'check_violation';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_lactation_overlap
    BEFORE INSERT OR UPDATE ON lactation_schedules
    FOR EACH ROW EXECUTE FUNCTION check_lactation_overlap();

-- =========================================================
--  TABLA: CALENDARDAYS (CALENDARIO LABORAL)
-- =========================================================
DROP TABLE IF EXISTS calendardays CASCADE;
CREATE TABLE calendardays (
    id SERIAL PRIMARY KEY,
    fecha DATE UNIQUE NOT NULL,
    estado SMALLINT DEFAULT 1, -- 0=feriado, 1=laborable, 2=recuperable
    descripcion VARCHAR(200),
    es_feriado_nacional BOOLEAN DEFAULT FALSE,
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER trg_calendardays_updated_at 
    BEFORE UPDATE ON calendardays 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

CREATE INDEX idx_calendardays_fecha ON calendardays(fecha);
CREATE INDEX idx_calendardays_estado ON calendardays(estado);

-- =========================================================
--  TABLA: ATTENDANCES (MARCAS DE ASISTENCIA) ZKTecoSync
-- =========================================================
DROP TABLE IF EXISTS attendances CASCADE;
CREATE TABLE attendances (
    id SERIAL PRIMARY KEY,
    dni VARCHAR(20) NOT NULL,
    nombre VARCHAR(200),
    fechahora TIMESTAMPTZ NOT NULL,
    fecha DATE NOT NULL,
    hora TIME NOT NULL,
    reloj VARCHAR(20) DEFAULT 'reloj1',
    user_id INT REFERENCES users(id),
    tipo_marcaje tipo_marcaje DEFAULT 'INGRESO',
    mensaje TEXT,
    procesado BOOLEAN DEFAULT FALSE,
    estado SMALLINT DEFAULT 1,
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER trg_attendances_updated_at 
    BEFORE UPDATE ON attendances 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

-- Trigger para actualizar fecha y hora automáticamente
CREATE OR REPLACE FUNCTION actualizar_fecha_hora_attendance()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fecha := NEW.fechahora::date;
    NEW.hora := NEW.fechahora::time;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_attendance_fecha_hora
    BEFORE INSERT OR UPDATE OF fechahora ON attendances
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_hora_attendance();

CREATE INDEX idx_attendances_user_fecha ON attendances(user_id, fecha);
CREATE INDEX idx_attendances_dni_fecha ON attendances(dni, fecha);

-- =========================================================
--  TABLA: DAILYATTENDANCES (ASISTENCIA DIARIA PROCESADA)
-- =========================================================
DROP TABLE IF EXISTS dailyattendances CASCADE;
CREATE TABLE dailyattendances (
    id SERIAL PRIMARY KEY,
    fecha DATE NOT NULL,
    anio INT NOT NULL,
    mes INT NOT NULL,
    horaini TIME, -- Hora real de entrada
    horafin TIME, -- Hora real de salida
    nummarca INT DEFAULT 0,
    obs TEXT,
    mintarde INT DEFAULT 0, -- Minutos tarde (sin tolerancia)
    retarde INT DEFAULT 0, -- Minutos de tolerancia aplicados
    minutos_lactancia INT DEFAULT 0,
    modo_lactancia lactancia_mode,
    doc TEXT,
    final TEXT, -- = igual que obs
    horaint TEXT, -- Todas las marcaciones del día (formato JSON o separado por comas)
    flaglab SMALLINT DEFAULT 1, -- 1=laborable, 0=no laborable
    horaslab DECIMAL(5,2), -- Horas laboradas
    minlab INT, -- Minutos laborados
    horas_extras DECIMAL(5,2) DEFAULT 0,
    estado SMALLINT DEFAULT 1,
    jobassignment_id INT NOT NULL REFERENCES jobassignments(id),
    usercrea INT,
    usermod INT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(jobassignment_id, fecha)
);

CREATE TRIGGER trg_dailyattendances_updated_at 
    BEFORE UPDATE ON dailyattendances 
    FOR EACH ROW EXECUTE FUNCTION actualizar_updated_at();

CREATE INDEX idx_dailyattendances_job_fecha ON dailyattendances(jobassignment_id, fecha);
CREATE INDEX idx_dailyattendances_anio_mes ON dailyattendances(anio, mes);

    FOR EACH ROW EXECUTE FUNCTION validar_cargos_simultaneos();

-- =========================================================
--  VISTA: HORARIO ESPERADO CON LACTANCIA Y TOLERANCIA
-- =========================================================
CREATE OR REPLACE VIEW vw_horario_esperado AS
WITH horarios_base AS (
    SELECT 
        ja.id as job_id,
        ja.user_id,
        cd.fecha,
        ws.horaini,
        ws.horafin,
        ws.tolerancia_min,
        cd.estado as tipo_dia
    FROM jobassignments ja
    JOIN workschedules ws ON ws.id = ja.workschedule_id
    JOIN calendardays cd ON cd.fecha BETWEEN ja.fechaini AND COALESCE(ja.fechafin, CURRENT_DATE + INTERVAL '1 year')
    WHERE ja.estado = 1
),
lactancia_activa AS (
    SELECT 
        hb.job_id,
        hb.fecha,
        ls.minutos_diarios,
        ls.modo
    FROM horarios_base hb
    JOIN permissions p ON p.user_id = hb.user_id AND p.estado = 1
    JOIN permissiontypes pt ON pt.id = p.permissiontype_id AND pt.codigo = 'LACTANCIA'
    JOIN lactation_schedules ls ON ls.permission_id = p.id
    WHERE hb.fecha BETWEEN p.fechaini AND p.fechafin
    AND hb.fecha BETWEEN ls.fecha_desde AND ls.fecha_hasta
)
SELECT 
    hb.job_id,
    hb.user_id,
    hb.fecha,
    hb.horaini as hora_entrada_base,
    hb.horafin as hora_salida_base,
    hb.tolerancia_min,
    hb.tipo_dia,
    COALESCE(la.minutos_diarios, 0) as minutos_lactancia,
    la.modo as modo_lactancia,
    -- Hora de entrada esperada (considerando lactancia)
    CASE 
        WHEN la.modo = 'INICIO' THEN (hb.horaini + (la.minutos_diarios || ' minutes')::interval)::time
        ELSE hb.horaini
    END as hora_entrada_esperada,
    -- Hora de salida esperada (considerando lactancia)
    CASE 
        WHEN la.modo = 'FIN' THEN (hb.horafin - (la.minutos_diarios || ' minutes')::interval)::time
        ELSE hb.horafin
    END as hora_salida_esperada,
    -- Hora máxima de entrada (con tolerancia)
    CASE 
        WHEN la.modo = 'INICIO' THEN (hb.horaini + (la.minutos_diarios + hb.tolerancia_min || ' minutes')::interval)::time
        ELSE (hb.horaini + (hb.tolerancia_min || ' minutes')::interval)::time
    END as hora_entrada_maxima,
    -- Hora mínima de salida (considerando lactancia FIN)
    CASE 
        WHEN la.modo = 'FIN' THEN (hb.horafin - (la.minutos_diarios + hb.tolerancia_min || ' minutes')::interval)::time
        ELSE (hb.horafin - (hb.tolerancia_min || ' minutes')::interval)::time
    END as hora_salida_minima
FROM horarios_base hb
LEFT JOIN lactancia_activa la ON la.job_id = hb.job_id AND la.fecha = hb.fecha;

-- =========================================================
--  FUNCIÓN: PROCESAR ASISTENCIA DIARIA
-- =========================================================
CREATE OR REPLACE FUNCTION procesar_asistencia_diaria(p_job_id INT, p_fecha DATE)
RETURNS VOID AS $$
DECLARE
    v_horario RECORD;
    v_entrada TIME;
    v_salida TIME;
    v_num_marcas INT;
    v_minutos_tarde INT := 0;
    v_minutos_tolerancia INT := 0;
    v_minutos_laborados INT := 0;
    v_horas_laboradas DECIMAL(5,2) := 0;
    v_horas_extras DECIMAL(5,2) := 0;
    v_hora_salida_final TIME;
    v_flaglab SMALLINT;
    v_todas_marcas TEXT := '';
    v_marca RECORD;
BEGIN
    -- Obtener horario esperado
    SELECT * INTO v_horario
    FROM vw_horario_esperado
    WHERE job_id = p_job_id AND fecha = p_fecha;
    
    IF NOT FOUND THEN
        RAISE WARNING 'No se encontró horario para job_id % en fecha %', p_job_id, p_fecha;
        RETURN;
    END IF;
    
    -- Determinar si es día laborable
    v_flaglab := CASE WHEN v_horario.tipo_dia = 1 THEN 1 ELSE 0 END;
    
    -- Obtener marcas del día y construir string de todas las marcas
    SELECT 
        COUNT(*),
        MIN(hora),
        MAX(hora)
    INTO v_num_marcas, v_entrada, v_salida
    FROM attendances a
    JOIN jobassignments ja ON ja.user_id = a.user_id
    WHERE ja.id = p_job_id
    AND a.fecha = p_fecha
    AND a.estado = 1;
    
    -- Construir string con todas las marcas del día
    FOR v_marca IN 
        SELECT hora, tipo_marcaje
        FROM attendances a
        JOIN jobassignments ja ON ja.user_id = a.user_id
        WHERE ja.id = p_job_id
        AND a.fecha = p_fecha
        AND a.estado = 1
        ORDER BY hora
    LOOP
        IF v_todas_marcas != '' THEN
            v_todas_marcas := v_todas_marcas || ',';
        END IF;
        v_todas_marcas := v_todas_marcas || v_marca.hora::TEXT || '(' || v_marca.tipo_marcaje || ')';
    END LOOP;
    
    -- Solo procesar si es día laborable
    IF v_flaglab = 1 AND v_entrada IS NOT NULL THEN
        -- Calcular minutos tarde considerando lactancia y tolerancia
        -- Para lactancia INICIO: se permite llegar hasta hora_entrada_maxima sin penalización
        -- Para otros casos: se calcula respecto a hora_entrada_esperada
        IF v_horario.modo_lactancia = 'INICIO' THEN
            -- En modo INICIO, solo es tarde si llega después de hora_entrada_maxima
            v_minutos_tarde := GREATEST(0, 
                EXTRACT(EPOCH FROM (v_entrada - v_horario.hora_entrada_maxima))::INT / 60);
            -- En este caso, la tolerancia ya está incluida en hora_entrada_maxima
            v_minutos_tolerancia := 0;
        ELSE
            -- Calcular minutos tarde respecto a hora esperada
            v_minutos_tarde := GREATEST(0, 
                EXTRACT(EPOCH FROM (v_entrada - v_horario.hora_entrada_esperada))::INT / 60);
            -- Aplicar tolerancia normal
            v_minutos_tolerancia := LEAST(v_horario.tolerancia_min, v_minutos_tarde);
        END IF;
        
        -- Calcular hora de salida final (base + recuperación)
        IF v_horario.modo_lactancia = 'INICIO' THEN
            -- En modo INICIO, la hora de salida es la esperada (ya incluye lactancia)
            -- Solo se agrega recuperación si llegó tarde después de hora_entrada_maxima
            v_hora_salida_final := (v_horario.hora_salida_esperada + 
                (v_minutos_tarde || ' minutes')::interval)::time;
        ELSIF v_horario.modo_lactancia = 'FIN' THEN
            -- En modo FIN, la hora de salida esperada ya considera la lactancia
            -- Solo agregar recuperación de tolerancia si llegó tarde
            v_hora_salida_final := (v_horario.hora_salida_esperada + 
                (v_minutos_tolerancia || ' minutes')::interval)::time;
        ELSE
            -- Para casos sin lactancia, agregar recuperación de tolerancia
            v_hora_salida_final := (v_horario.hora_salida_esperada + 
                (v_minutos_tolerancia || ' minutes')::interval)::time;
        END IF;
        
        -- Calcular horas laboradas
        IF v_salida IS NOT NULL THEN
            v_minutos_laborados := GREATEST(0,
                EXTRACT(EPOCH FROM (v_salida - v_entrada))::INT / 60);
            v_horas_laboradas := ROUND(v_minutos_laborados::DECIMAL / 60, 2);
            
            -- Calcular horas extras
            IF v_salida > v_hora_salida_final THEN
                v_horas_extras := ROUND(
                    EXTRACT(EPOCH FROM (v_salida - v_hora_salida_final))::DECIMAL / 3600, 2);
            END IF;
        END IF;
    END IF;
    
    -- Insertar o actualizar registro diario
    INSERT INTO dailyattendances (
        jobassignment_id, fecha, anio, mes, horaini, horafin, nummarca,
        mintarde, retarde, minutos_lactancia, modo_lactancia,
        flaglab, horaslab, minlab, horas_extras, horaint, final, estado
    ) VALUES (
        p_job_id, p_fecha, 
        EXTRACT(YEAR FROM p_fecha)::INT,
        EXTRACT(MONTH FROM p_fecha)::INT,
        v_entrada, v_salida, COALESCE(v_num_marcas, 0),
        v_minutos_tarde, v_minutos_tolerancia,
        COALESCE(v_horario.minutos_lactancia, 0), v_horario.modo_lactancia,
        v_flaglab, v_horas_laboradas, v_minutos_laborados, v_horas_extras, v_todas_marcas, 1, 1
    )
    ON CONFLICT (jobassignment_id, fecha) DO UPDATE SET
        horaini = EXCLUDED.horaini,
        horafin = EXCLUDED.horafin,
        nummarca = EXCLUDED.nummarca,
        mintarde = EXCLUDED.mintarde,
        retarde = EXCLUDED.retarde,
        minutos_lactancia = EXCLUDED.minutos_lactancia,
        modo_lactancia = EXCLUDED.modo_lactancia,
        flaglab = EXCLUDED.flaglab,
        horaslab = EXCLUDED.horaslab,
        minlab = EXCLUDED.minlab,
        horas_extras = EXCLUDED.horas_extras,
        horaint = EXCLUDED.horaint,
        final = 1,
        estado = 1,
        updated_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
--  DATOS INICIALES
-- =========================================================

-- Tipos de permisos
INSERT INTO permissiontypes (codigo, descripcion, permite_doble_cargo, requiere_programacion, minutos_diarios_default, dias_maximo) VALUES
('LSG', 'Licencia Sin Goce de Haber', TRUE, FALSE, NULL, NULL),
('LACTANCIA', 'Licencia por Lactancia', FALSE, TRUE, 60, 365),
('VACACIONES', 'Vacaciones Anuales', FALSE, FALSE, NULL, 30),
('ENFERMEDAD', 'Licencia por Enfermedad', FALSE, FALSE, NULL, 90),
('MATERNIDAD', 'Licencia por Maternidad', FALSE, FALSE, NULL, 98)
ON CONFLICT (codigo) DO NOTHING;

-- Horarios estándar
INSERT INTO workschedules (descripcion, horaini, horafin, tolerancia_min, horas_jornada) VALUES
('Horario 8:00-16:45', '08:00:00', '16:45:00', 16, 8.75),
('Horario 8:00-13:00', '08:00:00', '13:00:00', 16, 5.0),
('Horario 13:00-18:00', '13:00:00', '18:00:00', 16, 5.0),
('Horario 8:15-17:15', '08:15:00', '17:15:00', 16, 8.0),
('Horario 8:00-15:00', '08:00:00', '15:00:00', 16, 7.0),
('Horario 8:30-17:15', '08:30:00', '17:15:00', 16, 8.75),
('Horario 9:00-17:45', '09:00:00', '17:45:00', 16, 8.75)
ON CONFLICT DO NOTHING;

-- =========================================================
--  GENERAR CALENDARIO 2025
-- =========================================================
CREATE OR REPLACE FUNCTION generar_calendario_2025()
RETURNS VOID AS $$
DECLARE
    fecha_actual DATE := '2025-01-01';
    fecha_fin DATE := '2025-12-31';
    dia_semana INT;
    tipo_dia SMALLINT;
    descripcion_dia TEXT;
BEGIN
    WHILE fecha_actual <= fecha_fin LOOP
        dia_semana := EXTRACT(DOW FROM fecha_actual); -- 0=domingo, 6=sábado
        
        -- Determinar tipo de día
        CASE 
            -- Feriados nacionales 2025 (Perú)
            WHEN fecha_actual = '2025-01-01' THEN 
                tipo_dia := 0; descripcion_dia := 'Año Nuevo';
            WHEN fecha_actual = '2025-04-17' THEN 
                tipo_dia := 0; descripcion_dia := 'Jueves Santo';
            WHEN fecha_actual = '2025-04-18' THEN 
                tipo_dia := 0; descripcion_dia := 'Viernes Santo';
            WHEN fecha_actual = '2025-05-01' THEN 
                tipo_dia := 0; descripcion_dia := 'Día del Trabajador';
            WHEN fecha_actual = '2025-06-29' THEN 
                tipo_dia := 0; descripcion_dia := 'San Pedro y San Pablo';
            WHEN fecha_actual = '2025-07-28' THEN 
                tipo_dia := 0; descripcion_dia := 'Fiestas Patrias';
            WHEN fecha_actual = '2025-07-29' THEN 
                tipo_dia := 0; descripcion_dia := 'Fiestas Patrias';
            WHEN fecha_actual = '2025-08-30' THEN 
                tipo_dia := 0; descripcion_dia := 'Santa Rosa de Lima';
            WHEN fecha_actual = '2025-10-08' THEN 
                tipo_dia := 0; descripcion_dia := 'Combate de Angamos';
            WHEN fecha_actual = '2025-11-01' THEN 
                tipo_dia := 0; descripcion_dia := 'Todos los Santos';
            WHEN fecha_actual = '2025-12-08' THEN 
                tipo_dia := 0; descripcion_dia := 'Inmaculada Concepción';
            WHEN fecha_actual = '2025-12-25' THEN 
                tipo_dia := 0; descripcion_dia := 'Navidad';
            -- Fines de semana
            WHEN dia_semana IN (0, 6) THEN 
                tipo_dia := 0; 
                descripcion_dia := CASE WHEN dia_semana = 0 THEN 'Domingo' ELSE 'Sábado' END;
            -- Días laborables
            ELSE 
                tipo_dia := 1; descripcion_dia := 'Día laborable';
        END CASE;
        
        INSERT INTO calendardays (fecha, estado, descripcion, es_feriado_nacional)
        VALUES (fecha_actual, tipo_dia, descripcion_dia, 
                CASE WHEN tipo_dia = 0 AND descripcion_dia NOT IN ('Sábado', 'Domingo') THEN TRUE ELSE FALSE END)
        ON CONFLICT (fecha) DO UPDATE SET
            estado = EXCLUDED.estado,
            descripcion = EXCLUDED.descripcion,
            es_feriado_nacional = EXCLUDED.es_feriado_nacional;
        
        fecha_actual := fecha_actual + INTERVAL '1 day';
    END LOOP;
    
    RAISE NOTICE 'Calendario 2025 generado exitosamente';
END;
$$ LANGUAGE plpgsql;

-- Ejecutar generación del calendario
SELECT generar_calendario_2025();

-- =========================================================
--  DATOS DE PRUEBA
-- =========================================================

-- Usuarios de prueba
/*INSERT INTO users (dni, email, password, nombre, apellidos, role, genero, usercrea) VALUES
('12345678', 'admin@institucion.gob.pe', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 
 'Juan Carlos', 'Administrador López', 'administrador', 'M', 1),
('41567460', 'karina.marmolejo@institucion.gob.pe', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 
 'Karina Elbia', 'Marmolejo Tito', 'usuario', 'F', 1),
('41819548', 'robert.rojas@institucion.gob.pe', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 
 'Robert Nilton', 'Rojas Santos', 'usuario', 'M', 1),
('55667788', 'ana.torres@institucion.gob.pe', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 
 'Ana Lucía', 'Torres Vásquez', 'usuario', 'F', 1),
('99887766', 'luis.mendoza@institucion.gob.pe', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 
 'Luis Fernando', 'Mendoza Silva', 'SUPERVISOR', 'M', 1)
ON CONFLICT (dni) DO NOTHING;

-- Asignaciones de trabajo
INSERT INTO jobassignments (modalidad, cargo, area, equipo, jefe, fechaini, fechafin, user_id, workschedule_id, salario, usercrea) VALUES
('CAS', 'Analista de Sistemas', 'Tecnología', 'Desarrollo', 'Luis Mendoza', '2025-01-01', NULL, 2, 1, 3500.00, 1),
('CAP', 'Contador', 'Finanzas', 'Contabilidad', 'Luis Mendoza', '2025-01-01', '2025-12-31', 3, 1, 4000.00, 1),
('NOMBRADO', 'Asistente Administrativo', 'Administración', 'Secretaría', 'Luis Mendoza', '2025-01-01', NULL, 4, 1, 2800.00, 1),
('CAS', 'Supervisor General', 'Administración', 'Dirección', 'Director', '2025-01-01', NULL, 5, 1, 5500.00, 1)
ON CONFLICT DO NOTHING;

-- Permiso de lactancia para JENIFFER JULISSA 
INSERT INTO permissions (abrevia, descripcion, fechaini, fechafin, estado, jobassignment_id, user_id, permissiontype_id, usercrea) VALUES
('LACT', 'Licencia por lactancia - 1 hora diaria', '2025-01-15', '2025-12-31', 1, 281, 1030, 2, 1)
ON CONFLICT DO NOTHING;

-- Programación de lactancia para JENIFFER JULISSA - Ejemplo de cambio de modo por períodos
INSERT INTO lactation_schedules (permission_id, fecha_desde, fecha_hasta, modo, minutos_diarios, observaciones, usercrea) VALUES
-- Primer mes: modo INICIO (llega 1 hora después)
(1, '2025-01-15', '2025-12-31', 'INICIO', 60, 'todo los meses - entrada 1 hora después (9:00 AM)', 1),
-- Segundo mes: modo FIN (sale 1 hora antes) 
(1, '2025-02-15', '2025-03-14', 'FIN', 60, 'Segundo mes - salida 1 hora antes (4:00 PM)', 1),
-- Tercer mes: vuelve a modo INICIO
(1, '2025-03-15', '2025-04-14', 'INICIO', 60, 'Tercer mes - entrada 1 hora después (9:00 AM)', 1),
-- Resto del año: modo FIN
(1, '2025-04-15', '2025-12-31', 'FIN', 60, 'Resto del año - salida 1 hora antes (4:00 PM)', 1)
ON CONFLICT DO NOTHING;

-- Permiso de lactancia para Ana (ejemplo adicional)
INSERT INTO permissions (abrevia, descripcion, fechaini, fechafin, estado, jobassignment_id, user_id, permissiontype_id, usercrea) VALUES
('LACT-ANA', 'Licencia por lactancia - Ana Torres', '2025-03-01', '2025-08-31', 1, 3, 4, 2, 1)
ON CONFLICT DO NOTHING;

-- Programación de lactancia para Ana - Cambios trimestrales
INSERT INTO lactation_schedules (permission_id, fecha_desde, fecha_hasta, modo, minutos_diarios, observaciones, usercrea) VALUES
-- Primer trimestre: modo INICIO
(2, '2025-03-01', '2025-05-31', 'INICIO', 60, 'Primer trimestre - entrada retrasada', 1),
-- Segundo trimestre: modo FIN  
(2, '2025-06-01', '2025-08-31', 'FIN', 60, 'Segundo trimestre - salida anticipada', 1)
ON CONFLICT DO NOTHING;

-- Permiso LSG para Carlos (para permitir segundo cargo)
INSERT INTO permissions (abrevia, descripcion, fechaini, fechafin, estado, jobassignment_id, user_id, permissiontype_id, usercrea) VALUES
('LSG', 'Licencia sin goce para segundo empleo', '2025-02-01', '2025-11-30', 1, 2, 3, 1, 1)
ON CONFLICT DO NOTHING;

-- Segundo cargo para Carlos (permitido por LSG)
INSERT INTO jobassignments (modalidad, cargo, area, equipo, jefe, fechaini, fechafin, user_id, workschedule_id, salario, usercrea) VALUES
('CONSULTOR', 'Consultor Externo', 'Proyectos', 'Consultoría', 'Director Externo', '2025-02-01', '2025-11-30', 3, 3, 2000.00, 1)
ON CONFLICT DO NOTHING;

-- Marcas de asistencia de ejemplo
INSERT INTO attendances (dni, nombre, fechahora, reloj, user_id, tipo_marcaje, usercrea) VALUES
-- Karina (con lactancia - debe llegar a las 9:00 en lugar de 8:00)
('41567460', 'Karina Elbia Marmolejo Tito', '2025-01-20 09:05:00', 'reloj1', 2, 'INGRESO', 1),
('41567460', 'Karina Elbia Marmolejo Tito', '2025-01-20 17:00:00', 'reloj1', 2, 'SALIDA', 1),
-- Robert (llegada con tolerancia)
('41819548', 'Robert Nilton Rojas Santos', '2025-01-20 08:12:00', 'reloj1', 3, 'INGRESO', 1),
('41819548', 'Robert Nilton Rojas Santos', '2025-01-20 17:12:00', 'reloj1', 3, 'SALIDA', 1),
-- Ana (llegada puntual)
('55667788', 'Ana Lucía Torres Vásquez', '2025-01-20 07:58:00', 'reloj1', 4, 'INGRESO', 1),
('55667788', 'Ana Lucía Torres Vásquez', '2025-01-20 17:02:00', 'reloj1', 4, 'SALIDA', 1),
-- Luis (supervisor)
('99887766', 'Luis Fernando Mendoza Silva', '2025-01-20 07:55:00', 'reloj1', 5, 'INGRESO', 1),
('99887766', 'Luis Fernando Mendoza Silva', '2025-01-20 18:30:00', 'reloj1', 5, 'SALIDA', 1)
ON CONFLICT DO NOTHING;

-- Procesar asistencia diaria para los ejemplos
SELECT procesar_asistencia_diaria(1, '2025-01-20'); -- María
SELECT procesar_asistencia_diaria(2, '2025-01-20'); -- Carlos
SELECT procesar_asistencia_diaria(3, '2025-01-20'); -- Ana
SELECT procesar_asistencia_diaria(4, '2025-01-20'); -- Luis
*/
-- =========================================================
--  VISTAS ÚTILES PARA REPORTES
-- =========================================================

-- Vista resumen de asistencia diaria
CREATE OR REPLACE VIEW vw_resumen_asistencia AS
SELECT 
    da.fecha,
    u.dni,
    u.nombre || ' ' || COALESCE(u.apellidos, '') as nombre_completo,
    ja.cargo,
    ja.area,
    ws.descripcion as horario,
    da.horaini as hora_entrada_real,
    da.horafin as hora_salida_real,
    da.mintarde as minutos_tarde,
    da.retarde as minutos_tolerancia_aplicada,
    da.minutos_lactancia,
    da.modo_lactancia,
    da.horaslab as horas_trabajadas,
    da.horas_extras,
    da.horaint as todas_las_marcas,
    CASE da.flaglab WHEN 1 THEN 'Laborable' ELSE 'No Laborable' END as tipo_dia,
    da.nummarca as numero_marcas
FROM dailyattendances da
JOIN jobassignments ja ON ja.id = da.jobassignment_id
JOIN users u ON u.id = ja.user_id
JOIN workschedules ws ON ws.id = ja.workschedule_id
WHERE da.estado = 1
ORDER BY da.fecha DESC, u.nombre;

-- Vista de permisos activos
CREATE OR REPLACE VIEW vw_permisos_activos AS
SELECT 
    p.id,
    u.dni,
    u.nombre || ' ' || COALESCE(u.apellidos, '') as nombre_completo,
    pt.descripcion as tipo_permiso,
    p.fechaini,
    p.fechafin,
    p.descripcion,
    CASE p.estado 
        WHEN 0 THEN 'Pendiente'
        WHEN 1 THEN 'Aprobado'
        WHEN 2 THEN 'Rechazado'
    END as estado_permiso,
    ja.cargo,
    ja.area
FROM permissions p
JOIN users u ON u.id = p.user_id
JOIN permissiontypes pt ON pt.id = p.permissiontype_id
LEFT JOIN jobassignments ja ON ja.id = p.jobassignment_id
WHERE p.fechafin >= CURRENT_DATE
ORDER BY p.fechaini DESC;

-- Vista de empleados con doble cargo (LSG)
CREATE OR REPLACE VIEW vw_empleados_doble_cargo AS
SELECT 
    u.dni,
    u.nombre || ' ' || COALESCE(u.apellidos, '') as nombre_completo,
    COUNT(ja.id) as numero_cargos,
    STRING_AGG(ja.cargo || ' (' || ja.area || ')', ', ') as cargos,
    p.fechaini as fecha_inicio_lsg,
    p.fechafin as fecha_fin_lsg
FROM users u
JOIN jobassignments ja ON ja.user_id = u.id AND ja.estado = 1
JOIN permissions p ON p.user_id = u.id AND p.estado = 1
JOIN permissiontypes pt ON pt.id = p.permissiontype_id AND pt.codigo = 'LSG'
WHERE ja.fechaini <= COALESCE(ja.fechafin, CURRENT_DATE)
AND CURRENT_DATE BETWEEN p.fechaini AND p.fechafin
GROUP BY u.id, u.dni, u.nombre, u.apellidos, p.fechaini, p.fechafin
HAVING COUNT(ja.id) > 1;

-- =========================================================
--  COMENTARIOS FINALES Y DOCUMENTACIÓN
-- =========================================================

/*
CARACTERÍSTICAS IMPLEMENTADAS:

✅ REGLA LSG: 
   - Un trabajador puede tener dos cargos simultáneos SOLO si tiene LSG aprobado
   - La validación se hace automáticamente con triggers

✅ LACTANCIA FLEXIBLE:
   - Modo 'INICIO': La madre llega 1 hora después del horario normal
   - Modo 'FIN': La madre sale 1 hora antes del horario normal
   - Programación por rangos de fechas
   - Máximo 1 año de duración

✅ TOLERANCIA 15 MINUTOS:
   - Los empleados pueden llegar hasta 15 min tarde
   - Deben recuperar esos minutos al final de la jornada
   - Cálculo automático en la función procesar_asistencia_diaria()

✅ CAMPOS DE AUDITORÍA:
   - Todas las tablas tienen: usercrea, usermod, created_at, updated_at
   - Triggers automáticos para actualizar updated_at

✅ CALENDARIO 2025:
   - Todos los días del año 2025
   - Feriados nacionales del Perú incluidos
   - Clasificación: laborable, feriado, recuperable

✅ DATOS DE PRUEBA:
   - 5 usuarios con diferentes roles
   - 4 asignaciones de trabajo
   - Ejemplo de lactancia programada
   - Ejemplo de LSG con doble cargo
   - Marcas de asistencia de muestra

FUNCIONES PRINCIPALES:
- validar_cargos_simultaneos(): Evita doble cargo sin LSG
- procesar_asistencia_diaria(): Calcula asistencia con todas las reglas
- generar_calendario_2025(): Crea el calendario completo

VISTAS ÚTILES:
- vw_horario_esperado: Horarios con lactancia y tolerancia
- vw_resumen_asistencia: Reporte diario de asistencia
- vw_permisos_activos: Permisos vigentes
- vw_empleados_doble_cargo: Empleados con LSG y doble cargo

PARA USAR:
1. Ejecutar este script en PostgreSQL 12+
2. Los datos de prueba están listos para usar
3. Llamar a procesar_asistencia_diaria(job_id, fecha) para procesar asistencia
4. Las vistas proporcionan reportes listos para usar
*/

-- Mensaje final
-- =====================================================
-- DATOS DE USUARIOS Y ASIGNACIONES DE TRABAJO
-- =====================================================
-- Datos extraídos de tb_usuario_local.csv
-- Total de registros: 383 usuarios
-- Codificación: UTF-8

-- Insertar usuarios desde CSV
-- INSERT statements para tabla users
-- Generado automáticamente desde tb_usuario_local.csv
-- Codificación: UTF-8

INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (193, '07929370', '07929370', '$2y$10$CBQETcUoPfpi.3PkKPLWeOJqbXi/8SR4wccx7SkHGb77yMz9TFizK', 'OFELIA OTACIANA', 'AGURTO AYALA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (310, '40775861', '40775861', '$2y$10$S2iOUjMDj09g92OSGz4yku71NK2DXfw5.h1PMvWqAcxyuW8OvXSj.', 'DEISY', 'ALTAMIRANO GONZALES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (166, '07108639', '07108639', '$2y$10$rXp2XBVf53EthtcYna2hteKqmlsGDG5WTCTKJrzOeJKLZTc6erY5K', 'SOFIA SONIA', 'ALVAREZ ORAHULIO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (292, '25828325', '25828325', '$2y$10$HMbsl1iqhw2S5xZh3uDS4eWhOAaxBC4vEovuhfQyHRy14ZT8LRqRC', 'PATRICIA MILAGRITOS', 'ANTICONA INGA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (237, '09616898', '09616898', '$2y$10$pojDtO8s/7QjE9tMcys3te2Zl/QV1SDB5q/QK1Ok43/VaaSSiitf2', 'MIRTHA KARINA', 'ARANA CARHUANCOTA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (188, '07759447', '07759447', '$2y$10$yDGlspMx/4oSfCJKNWa6VuNg8x30KEzMHaJCKK3Y9MEBJkzxHgPL.', 'FANNY LILIANA', 'ARIAS QUIROZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (246, '09967109', '09967109', '$2y$10$.iSuhEf8C03PxgnB9IHhLuUj1pWEpdSeipdUoZbMeNREJOt0oHazK', 'WILMAN CARLOS', 'AYALA POMA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (291, '25780801', '25780801', '$2y$10$Z3SJ7DqbL5c4lzysX2Gy8eN96bw0a9k06p3iDWZqOMtiHja7B8vHa', 'MARIA JULIA', 'BRAVO RETAMOZO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (224, '09232338', '09232338', '$2y$10$jaOnEXvOCEPPJ4D.xcVciuuhykKa7cTnwAi8LCbWa8XKiM./jIau6', 'ASUNCION ISABEL', 'CALIXTO AVILA,', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (229, '09494837', '09494837', '$2y$10$EQu/4YJEtV8eITEYNKEvreHUcpvel3Sw1vdsC5XIWT/jsLeokMUUe', 'ULISES', 'CANO CAMARENA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (584, '74240115', '74240115', '$2y$10$X4JzS7yk7rqeilRaQYEK1uuQz/JMzkVpQGs4i5YsmkjqloQ2FtyYO', 'KORAITA JOSSELYN', 'CARRASCO MARTÍNEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (163, '06798589', '06798589', '$2y$10$FqWqYt9aerTi6l0y5s0s3uDKuAhrc34pDYc2pm8GBDiEp7Hf1YP76', 'BLANCA NARCISA', 'CASTILLO VERGARA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (290, '25768496', '25768496', '$2y$10$KWmuK/s7CPI5i3r.982Vbeagan0OJXsVf9qVTCPkraJv4fmWDGuC.', 'ROSSANA', 'CASTRO MORI', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (870, '48630597', '48630597', '$2y$10$oyNS5rRw6WdfKHaMEGocnuE5yefM33Yscy7nxgmd/yBfWayMSrlVm', 'JEANPIERRE JOSAFAT', 'CELIZ GAMBOA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (428, '06244899', '06244899', '$2y$10$LG37sIT26H9Qd8fJizF7nu9Gqwduzr3kgOxpfOf3h0D6lFB/i6NF6', 'HÉCTOR FRANCISCO', 'CHAFLOQUE DIEZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (169, '07165109', '07165109', '$2y$10$MuxzMFw30NitzhtsvnnMvusBt8GP9Pv8oPat5Eih0A8QK.RxsBbsO', 'MARÍA CORNELIA', 'CHAUCA ALBUJAR', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (147, '06035644', '06035644', '$2y$10$EQ5F5M8yXrh9ENzjvFR6suXd8wVayR7lKv49j/6GI5NblXlIkwS5u', 'NORA MARGOT', 'CHOCCE CORONADO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (242, '09872584', '09872584', '$2y$10$O6Zf8OH5hr5u2H8jHmtwnOwqL6X1ttbdpNYKy2yHna1v4qy9f.f7G', 'DANIEL', 'CORDOVA DAVILA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (178, '07420376', '07420376', '$2y$10$NjmptaKcls4oMqIH0IyOFu12BJYc2F92n0dEgq0pAEXs0vXvQB/9S', 'LUZ MARÍA', 'CORDOVA MENDEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (182, '07496055', '07496055', '$2y$10$yV9MI7ffO67BzDyYskGDcu7XSnfLAeV61b9XAYUcKeODPSSAwpUF6', 'CONSUELO', 'CRUZ REYES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (183, '07506059', '07506059', '$2y$10$0t28vUNfpvNE2e0eLauHbeRonNmccUyuHFEIzGeydsc4x6lck.SRS', 'VIVIANA ISABEL', 'CUADROS PEREZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (420, '76177693', '76177693', '$2y$10$2l5A2fFSmAApileQ2jpOgeGVCz/C68uV.BvvJcDx6RYfZkrmRYg3W', 'LUIS PATRICIO', 'DURAN GASTIABURU', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (177, '07399296', '07399296', '$2y$10$y5S2.rM3byhP4.1/Oko8Pufbw0uJdC2/Q.WAQshXGeB/noH5ExTZq', 'DOROTHY JUANA', 'FALCON UVIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (160, '06743648', '06743648', '$2y$10$XXIrmrAT9C5.CltSzZs8C.zWgSgKt4bCRGLwcq3R2O2Y5qltpVCXW', 'AGUSTINA VICTORIA', 'FERNANDEZ CORONADO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (197, '08079887', '08079887', '$2y$10$7hu6f8MLYt7sPHe7TGyFq.IfaVFETTT9ILFJ0.7qoShXphz81zoCq', 'BENICIO VICTOR', 'GAMARRA RIVERA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (791, '08296859', '08296859', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'EDSON CIRO', 'GARCIA APARICIO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (150, '06201291', '06201291', '$2y$10$gvbsVSNPvHgjlbZHI1BV4.EQRtIcNpuVzUzk3qnIijOuBOmI/hcxC', 'GODOFREDO', 'GARCIA CASTILLO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (227, '09335905', '09335905', '$2y$10$rwFsa3jtQ/iaHqq3X.X1ou8De.zwIewKDig0vj0TU/uWWr7hRCZ4q', 'MARCELA', 'GONZALEZ CARRASCO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (427, '07260197', '07260197', '$2y$10$fLYYLYV9v4fpcYgSm4LvcOqBvCFYDTtNDiOJqvFoK3jaGncL1kWvq', 'ROSA ELIANA', 'GUERRA CORDOVA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (353, '44911434', '44911434', '$2y$10$9A/ola9F6rcFa3sgVBd4xuEwjy6Ibm1ff1r8rZxssL/X4eHlk9iHS', 'LIZ MILUSKA', 'GUTIERREZ SILVA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (192, '07903991', '07903991', '$2y$10$huL1jYiS3dZKKpVKAGqkRe/YOwYT057mAS..tgmwzC/aRzS/wtEw.', 'MARTIN', 'GUZMAN BRITTO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (261, '10734772', '10734772', '$2y$10$tDm6apP569RJdGrm/.eqYO3V/Giz1lQtgDhWmhBJJA.7kB.PLFgPe', 'AGUSTIN', 'HIJUELA JIMENEZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (873, '41548336', '41548336', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ANGELA ROSMERY', 'HUAMAN NAPANGO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (333, '43034662', '43034662', '$2y$10$RDaof/TmfZho.Q/UUfsJRuSKi5zZXlo0novo1MUPoSnuBcQ/LcAE.', 'URSULA VANESSA', 'KANEMATSU GRADOS', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (267, '15741588', '15741588', '$2y$10$hlgsramXVLvM0akndXj7guL5sszBs1StlhExyvHDF1YN7MfDKoOpy', 'LOZA CARLOS ALBERTO', 'LA ROSA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (167, '07121399', '07121399', '$2y$10$wp84qE.i7yGNHMCMgUshvuG9XyhDDt6IlrTvsrunowQlGTShKXfDC', 'AGUSTINA MARUJA', 'LANDECHO GARCIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (604, '07621313', '07621313', '$2y$10$MN9glc19XspJAtuoiTwpJuepqP9dupM79hGUhJPQUc7m6OTIkQ/HO', 'LIZANDRO ROAÑO', 'LAZARTE LAZARTE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (159, '06735596', '06735596', '$2y$10$G5I79ADgDBWiK8tlWuHP/.VKuL5Vk.QQG7KTsABPa4kBkIUBK0K2C', 'ROSA EDITH', 'LEVANO RAMOS', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (632, '09919326', '09919326', '$2y$10$0puzMBDiQIcWGoxLZgnE6.ULLEcD4zPjH8aMsskK8bXFlX2hCki02', 'ROSA', 'MARINGOTA ALVINO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (633, '72391962', '72391962', '$2y$10$DniTldeOEHgBMxvdNW0M5euis7HrKLLP8zoUxeOFoCpVxEuOtcW9S', 'MARIA DEL CARMEN', 'MEDINA NINA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (634, '10268230', '10268230', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CARMEN ROSA', 'MEDINA ROSAS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (221, '09079080', '09079080', '$2y$10$KD.fa24z7Dk4JWvPFG44wuXYuVVvUIns/H9EBiBel8f0rxYSvQwWS', 'CARMEN ROSA', 'MORENO REYES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (240, '09736096', '09736096', '$2y$10$HlV90E5Erhu5rGm/I032hejEY/fEOKgQyaWFVG8WUmRmev14YY7au', 'LUPE DELIA', 'ORTIZ CACCIRE', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (158, '06718343', '06718343', '$2y$10$no68jK3qLeUcciHUyodefemDHaFBJtI0pcdWENOrlQRnhn4n8RRl.', 'ZOLIA ROSA', 'ORTIZ CHAN', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (214, '08877411', '08877411', '$2y$10$5JXtw8dItsuqgeR2ATxBuOrvU4nzuIb/ZdMrFPWZrq0T4CR.oBCm.', 'DENISSE PATRICIA', 'ORTIZ CASILDO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (638, '10123801', '10123801', '$2y$10$I0sQihxYVjON0tUxQxUyCOwy7Ry5i6n.RmDYZ6qADIsl/3eqCXbdy', 'ERIKA YESENIA', 'PAJUELO ROSALES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (364, '45844057', '45844057', '$2y$10$CoQmj1Y29FhPpmbMSGkrweb9NnkkitcwlqSB7Y1WX.PT5c/5uKr3y', 'JUANA JESENIA', 'PALOMINO ZANABRIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (186, '07597479', '07597479', '$2y$10$sFRObubUKXMsXryjs/hu5u5c6MKqCOAJn5vipXH/VYGZWXd3fkCHO', 'LILY ROCIO', 'PEÑA SALAZAR', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (218, '09065518', '09065518', '$2y$10$r1WlW0Q6gFDrLZVCcfGB7.F6DDrnPi8Cjnv3pUN.OhH3Oef1okffG', 'NICOLAS FRACISCO', 'PEREZ ZAMORA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (439, '21419826', '21419826', '$2y$10$FR.TVlY/8fTiY9akFKLtCuabHZYO225cKg6uwyDx.xy9c9LnubqEe', 'GLADYS JULIA', 'PISCONTI SANCHEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (263, '10777197', '10777197', '$2y$10$Sp/p/rwyjd9PvUg03mKtcufKyKH9rZYkBQ7Cb.m/BdcDvQArvzy8C', 'MARGOT KANDY', 'POMA MORALES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (151, '06217641', '06217641', '$2y$10$oNHHOd0T6unqwpD9uv1ZZ.FF6eqZe4VQXrp2Bxb1yBqFP.DkNxCya', 'LIVIA BERNARDINA', 'QUIROZ CORNEJO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (225, '09275781', '09275781', '$2y$10$ekajpczq8.NOTVPi2Cu8pug7rJpN9n6QwBBQXd.Tl68LibfdrtmFq', 'JOSE ANTONIO', 'QUISPE VIZCARRA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (640, '15752113', '15752113', '$2y$10$vhCy4oj0FLxfCaQ4a/y43uuNpteP5kOZIaZ7SXUdtNysRk3DCsiAm', 'YLIANA MARYURI', 'RIVERA YABAR', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (179, '07429283', '07429283', '$2y$10$/D1RK1lKi0wbDw2fWoK1BuUotzMUddwTMPkGzlbx5Oz5WANXfkEQC', 'CONSTANTINA', 'ROMERO ESPINOZA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (204, '08614366', '08614366', '$2y$10$rE1defFHwyQH77wE5fKN8uw1ELnrkESfhYQSVbw3hEyEjIpE77Yru', 'MARITZA RAQUEL', 'ROMERO RAMOS', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (326, '41963763', '41963763', '$2y$10$fWPJIvIBsRpPMgopOZQwXe3Mamp0OcDUKjEnQm8zScSIxhr6BInoW', 'JAQUELINE ELIZABETH', 'SAAVEDRA TORRES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (282, '22896125', '22896125', '$2y$10$oL9iMt06iTouqwOOsFOPa.l67Xrc/D.Rome1w.hK9UdZ/jLcy/o5i', 'LUZ', 'SALAS EULOGIO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (872, '47851117', '47851117', '$2y$10$uoa81T8HZAw6fLtPjDhbQejq2vWNkwCLl0W4rrapC7254ek5.qn7K', 'ELIZABETH', 'SALAZAR RODRIGUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (200, '08395747', '08395747', '$2y$10$.vIc1n2SMxW9/HXvisCgGOboiEuE2sbWqOqobx4N/cb5HiTdAF.e.', 'MARIA DELFINA', 'SANCHEZ ORTIZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (602, '09491460', '09491460', '$2y$10$P7./iBSomQsoWpXpM6Voxe3CyvaryWALCZXsJ7eKwI0NK9C/CSM7u', 'CARLOS HERNAN', 'SANJINEZ ZAPATA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (644, '47112955', '47112955', '$2y$10$7rzv4pwsRZvz2yPDnL9Vue.d./mQoqsJ0sXyO/R6plIAJBxxftp2.', 'PAMELA JOSELIN', 'SHAPIAMA DÁVILA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (287, '25644675', '25644675', '$2y$10$TRhsQHNHlL8aPGK8OtWA1etqelb51q0q/CBvtRg.h2rInJftFTIdO', 'ROSA', 'SOLANO MENDOZA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (277, '21519998', '21519998', '$2y$10$9dPgkURZDFvy7L6EOWd0bueatrfZaakQlQjoK/XtAubJWmUYqwMAq', 'ROSA KAREN', 'SOTELO MORI', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (176, '07393743', '07393743', '$2y$10$jYzIc0ws420JfcX3uP/dp.fj2fgsnLv4esycJJnxPTw6iNFSSgjXa', 'JAVIER MAURICE', 'SOTO ECHEGARAY', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (789, '40098223', '40098223', '$2y$10$uKleel4YpAC4401u4feQF.j6wvmRdJmdsuz5hYRYL4d0g1gcSMTl2', 'ANSHELA JOVANY', 'TARRILLO DAVILA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (293, '31610877', '31610877', '$2y$10$TmyJ9fd/PZ4IVzhvVy/sm.FLc2.ivGQHHD29.bRcSMUWvGxR35Hze', 'VALENTINE TERESA', 'TORRES PICON', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (194, '07943895', '07943895', '$2y$10$QnclC8U7QwDjp46bhlzPjeGZLafMU6qo2NdV5HczmBBOHNBb5Wywy', 'ANA ROSARIO', 'VALDERRAMA BARRIENTOS', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (157, '06710057', '06710057', '$2y$10$Vz.zouGBFiqXrhCTMGLd6.FXi0hiQCaP4jKZKEc3.PLCzqhauiEfC', 'MIGUEL CARMEN BERTHA', 'VALLEJOS SAN', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (180, '07465482', '07465482', '$2y$10$go8PHbfduoq7H1URdjm1OuRg2e55YxUPcr03T418RLtebTAXaFYDq', 'MARIA ANGELICA', 'ZAVALA QUEREVALU', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (207, '08710651', '08710651', '$2y$10$bORRT7BvrzESe5CgBgUTJuilCnTjj1HOmDEww.nyaeOXOPJxXphXe', 'CARMEN OLFELINDA', 'ZELADA DAVILA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (217, '08923767', '08923767', '$2y$10$DWfTvEmuZFEgaO7UnT83UuDJB04mMB8Sn0f6R0YGuv8uHAUWSHt0C', 'CARMEN ROSA', 'ZUÑIGA LEANDRO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (209, '08810286', '08810286', '$2y$10$C3jA6VHwxZiIF1PjFW3/He15ltrSmgTGB0H7hbhEyef.56vDSFisK', 'CARLOS ALBERTO', 'ANGELES RAQUI', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (314, '41341613', '41341613', '$2y$10$F676UwFS3SbM//6UrzfWU.g48UWAPnsMSfDAIVy1nW/6KvmhBajUm', 'YAHAIRA', 'AREVALO SANCHEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (384, '47415821', '47415821', '$2y$10$GCQB6OQwnKlhOahc5GtlwetslTvxj7bE8AKcXEay45mrg.Nba0N3S', 'CINDY ROCIO', 'BONILLA BUSTAMANTE', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (185, '07537251', '07537251', '$2y$10$UCvlCnvWtWjOy6Y8s/O77Obh.gCrRecavyVa.8d0.iPWgSxmNzKoS', 'CARLOS JAIME', 'CABRERA ARANA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (320, '41769756', '41769756', '$2y$10$2mA7iaK4cTygFLV/ZJuu/eskCr2PS0k2hd/v6/0GLVWWrEKCsJ1Xq', 'ERIKA GIOVANA', 'CARTOLIN HUARACA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (386, '47624506', '47624506', '$2y$10$2..TTUTN2Eonnc8A6.RlDe7UsEzRVywTFZxj5hC.VaWqpbfPmmime', 'KATHERIN VIVIANA', 'CASAPAICO VELARDE', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (313, '41301171', '41301171', '$2y$10$vofVAdlaewcPElOxfja2eOz6s40Zcg3SRoylAX4FjBhoIQBokiPge', 'PABLO MIGUEL', 'GUARDAMINO SERRANO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (301, '40349561', '40349561', '$2y$10$dnOeJgPE.HzoTia.1CoYv.0krtFzLeO6fo0OllFGRA3W.lBcmJpmq', 'ROGER LEE', 'HUIDOBRO NIETO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (149, '06099648', '06099648', '$2y$10$S44v9ZI9cWgRSW.saN7diOxk0a.THdPEwxTtPpfNrTzhkjHOTXLNS', 'WILLIAM JAIME', 'IPARRAGUIRRE VILLANUEVA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (306, '40688974', '40688974', '$2y$10$SyasktHf.T4hL7Z49d1lq.jdrCHRL3MgAR/LMEvqjFncR4Nl36hHi', 'LUZ GIOVANNA', 'LOPEZ EGUIZABAL', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (444, '41567460', '41567460', '$2y$10$oPKMSF.NC5DGU1c1KU0rIuRIwjeVnmkaM1Q8SQ1nviKk1WS4uel5a', 'KARINA ELBIA', 'MARMOLEJO TITO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (239, '09689310', '09689310', '$2y$10$FBXFcS7Ar7yLb7Hmblw7..9uYN44l13EkSarBpmEBlL8YYudmT8Fm', 'ISABEL CRISTINA', 'MONZON APAZA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (300, '40309069', '40309069', '$2y$10$hssUcmLkk/KAARzh8xbFxegIpXCy/m3eIYt2usJByD2GEJW3r7IXq', 'FERNANDO MARTIN', 'PACORA PADILLA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (411, '72019730', '72019730', '$2y$10$RVKkKjLSIwFV5AQmraJa9OjeXX1YEHJK/t39ecqPeOhEdVJHFJP9u', 'SARITA ISLABEL', 'PORTILLA CORTEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (340, '43700180', '43700180', '$2y$10$7d.pG.sUGYZp/kwjnG3FbusxJ.oumjiSaldy2r0nBkvST6qtLNDBu', 'DEYSI', 'QUILCA ORONCOY', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (318, '41507068', '41507068', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ELVA ROCIO', 'QUILCA ORONCOY', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (358, '45393249', '45393249', '$2y$10$RpOCF9GJHR6dYFz1psvT2.gR0KjSUKFvZavY1i4aB2bz08ayyh3o6', 'LINA VICTORIA', 'RAMIREZ VEGA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (256, '10399384', '10399384', '$2y$10$0ugg0jJ7zFWaTohAdIHKVuuZaNPOLRXhK9dPB4AwRC6Qk02PyuXIC', 'FREDDY EVER', 'RAYMUNDO JUSTINIANO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (421, '76565198', '76565198', '$2y$10$6a1PmfxU1GyQPOGYQB2WHuSx5wkXqCSG6k4UPLY2SCd9DD8FJNVau', 'CINTHIA MAGALI', 'RETUERTO LEON', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (257, '10588382', '10588382', '$2y$10$xAfnJu5lr2bxZJmjfajzyOsF8YS0bhGgnURI/18W1M6HuffBqeIeC', 'MARCO ANTONIO', 'RIOS CACERES', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (155, '06270947', '06270947', '$2y$10$Yf/Ar8V4enfXygATHEDkgu6gLtR/oOYZ/VV7/gEzN1kcDTShgAweW', 'LUIS FELIPE', 'RIVERA HUAYLLA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (393, '48249107', '48249107', '$2y$10$wsB2o/Fyb6zn2KtusH/ozeXGNJk9v.v7V.RKLf6Evnuc1JsbF5oXi', 'RUDY LLANETH', 'ROJAS PEREZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (275, '20027831', '20027831', '$2y$10$NrJEBEAaQ6R9X7R32kXPJO64HbU17z6wKlgzuxVKCvoqLVrsNEPW.', 'JESUS MANUEL', 'SANTOS MONGE', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (191, '07869865', '07869865', '$2y$10$zoDZRXfbQlKjKlrsWGCYLemqC6NhQhjJEr3XMlMjZc7YaL1Tr6yIS', 'CARLA NICELY', 'TAFUR BRAVO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (252, '10244547', '10244547', '$2y$10$8L9E3lEgng0xz1vTo/7RyeE3pMOb3fKGLAnCIPm4yGWG061Lp2Yiq', 'MANUEL JESUS', 'TELLO DELGADO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (156, '06587801', '06587801', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'FREDY HUMBERTO', 'VEGA SEGURA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (271, '16164992', '16164992', '$2y$10$WZ2ZsQh88kXqeHv18Qonb.H1Bfd.76dtnY.JLX/UNvWofj.Ichjvu', 'ROSAURA ELISA', 'VILLA CAJAVILCA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (262, '10742147', '10742147', '$2y$10$AGZiqKONHQs5rykyZ.B4/.sQHdR6SJQRrPJ3ZRSCgibBtvHOX9TdK', 'RAQUEL', 'VIGO RIOS', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (416, '72852268', '72852268', '$2y$10$HRl3B6tAu9EOPwl9VJ/F..e4Vu4H7RUl3e2kD0aWemjr.m67MtHLi', 'PAOLA ROSARIO', 'SERRUTO CORONADO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (359, '45528426', '45528426', '$2y$10$Z1tBfi4RwVD4GX/DGG3qb.f6B348ORpXfXI90p3Ts1SNEtGDpoc/K', 'CELIA RAQUEL SALOME', 'BERNAL CABRERA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (170, '07187502', '07187502', '$2y$10$0dv1ccwvDw7hmKbpIlZJ8./viRdz5RQm1Ufp/syO.ZH/elvQM9bI2', 'VICTOR ALBERTO', 'GALINDO CABRERA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (345, '44143152', '44143152', '$2y$10$EjjZbJYbGH85c/Md/JUZaO3S1n8oz4pxtV.VdZB40wjWkDtjXAcbO', 'ELSA ZAIDA', 'HUAMANI SOTO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (274, '08684249', '08684249', '$2y$10$UOeQoAp69itl0Ki/sPmaaODsMUXNruVVxwkmmQdovFmdDNkXvTrvu', 'JORGE MERALDO', 'MENDOZA ZEVALLOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (347, '44273008', '44273008', '$2y$10$gfcZpKYlqTtyx2GM2a3kQ.UpUTOwBckGaGh2Jjil6KWsOm4CGVgBe', 'JORGE LUIS', 'CATAÑO ZAPATA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (144, '01174361', '01174361', '$2y$10$1yDmCX9uvP4UeYAF215tGeFNIvj6oZN.l3BP.rSjnA0kVMCM9JvKS', 'JUAN', 'URQUIA MESIA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (377, '46881735', '46881735', '$2y$10$XY/vbMwKVl4NSDbX3PawteF5PnhtbcGcMdT47YnOqPpeQRxustXia', 'STEFANY NATTALY', 'POVIS VALDIVIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (381, '47188096', '47188096', '$2y$10$IW0zudokS54k2AMmbIs1EOxMM3nC44gjiBzopejK69er7T6NDkGKK', 'DIANA CAROLINA', 'HERRERA VIENA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (198, '08163600', '08163600', '$2y$10$l/4a5XhwOGlITIEPyNdstOgrl3eiqJWXau3j1OA6kKebv.7cWwJf6', 'RICARDO ROMULO', 'SALCEDO SUAREZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (265, '10802932', '10802932', '$2y$10$revnS90vX/0.8izs9Kj6Ee..szd1RbDh7q53cCuRbtqnVzJPjKOl.', 'DAVID DANIEL', 'SALINAS BRIONES', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (302, '40384228', '40384228', '$2y$10$GzAKD6Z45TOAamYP3/X0xuES47J5CGssTmlZTYvidm0hixcoqvPyi', 'KAREN ROCIO', 'AGUILAR YARINGAÑO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (238, '09626369', '09626369', '$2y$10$Ts2Hm3D/ib0O7kVP6JtTb.8jpvsu7d8J4f20AXqAXUdkTmI0.DjGi', 'CESAR OMAR', 'PEREZ ESPEJO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (361, '45609550', '45609550', '$2y$10$Maf0f46HMYsC3WdPaMwu9u90g1KFj5iBjXF2/iZC5.Dv5WOsmwQZC', 'TANIA ROSSANA', 'SILVA PEREZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (308, '40718006', '40718006', '$2y$10$2tOx8iD3998n0qVNaZxfwun2Bj4Z.w6j7YFYgoDIJJclCSboE/v8i', 'LILIANA', 'FRETEL GUTIERREZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (234, '09585824', '09585824', '$2y$10$npXsZ1A4zmkULh0KeJXjyOEe9ZRNAU821CAfVKthqkPiVRSfOz5dy', 'CESAR AUGUSTO', 'AGUILAR QUISPE', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (339, '43617826', '43617826', '$2y$10$vXGRbdeQz.ApULAoMzWpu.y7isETFYu9sxnqsaxhhyBEjDF0FfQf6', 'NATHALIE DARLENE', 'SEMINARIO PALOMINO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (307, '40698230', '40698230', '$2y$10$ihMicl2DMoEARhF/iZ4kouyp9m4bn6pBGO1xCmnuuFJvoMDXXZLEe', 'MARIBEL SOLEDAD', 'CALDERON CARHUAS', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (376, '46762920', '46762920', '$2y$10$wQR5u73gUmBoE5GZQxXz3.9IthUMdWHIn.t5Bd6mei4FJFquNyI1C', 'EDISON DAVID', 'URBINA RAMOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (407, '70904857', '70904857', '$2y$10$cK5Rq7ZwyG9gP9U17ipeeOsB9rDtkSXuNJNaNI8QIMeBTHty0/txK', 'BLANCA MERCEDES', 'PLAZA CASTILLO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (311, '40952933', '40952933', '$2y$10$mWgvu4iqamAuIrxzDRyQMuag0njg0Zjo7QCa.Zl5josWcq4Bw.AP6', 'FLOR DE MALENA', 'CASTRO REATEGUI', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (323, '41819548', '41819548', '$2y$10$IpDI8Dqgy.vhwBYR/D8OgOn/0mR/Fxf2aeQRnB.HJgdMQ11WNU0WS', 'ROBERT NILTON', 'ROJAS SANTOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (189, '07764789', '07764789', '$2y$10$bjD3HnALSowZPjbCqiQleufgsctzGjSl.tZMrbx9gv9bF8xi52qEW', 'VICTOR DAVID', 'CORREA VILLALOBOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (397, '70182815', '70182815', '$2y$10$hj.S5hwmLkO8PCc.od5MTuJSdwnIPHWzo2QWogJffwgN9/BK4kVLm', 'JESUS ERNESTO', 'PEÑALVA VILLALOBOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (325, '41939825', '41939825', '$2y$10$dnFAex64HKUrM5YrVknxAuFFe6yV3GomxTlADb4LbdRfT8V933kSO', 'GUILLERMO HERLESS', 'MIRANDA MARIÑO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (244, '09948393', '09948393', '$2y$10$DGHqGfDCyFf48Hh6vqN5s.OFUK104kH15sAIizXpm7K8PE69K8ORm', 'JOSE LUIS', 'ESPINOZA PILCO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (226, '09277412', '09277412', '$2y$10$vcVR821y1UWchnbFAQd63OUAgyCi9a469m0lh4vjx0jXNMZgI4Z/C', 'RICHARD ALBERTO', 'LOPEZ RIOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (243, '09915071', '09915071', '$2y$10$cyV0hS55u/A.uUolUyRNmuhDRpCtf/oEpaF5pUMUtkqlMH2ij5xZq', 'PATRICIA JULIANA', 'VASQUEZ CABALLERO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (422, '77093343', '77093343', '$2y$10$vfyFKuPJ2iQ1uyD4UvHB9etUlo80udDT6yEsCW0jWsDFOpiN0jKz2', 'EDUARDO DAVID', 'MORENO RODRIGUEZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (219, '09067268', '09067268', '$2y$10$u5P4sHR6y1ulE8eiUo4ejuyvb6041zzOUJGVQqLPtCZT1MSJUUXmy', 'SABINA IVELA', 'ARTEAGA VALERIANO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (369, '46228473', '46228473', '$2y$10$zd6jWK.JLQF0rinmATtrG.5vkh5WFl.bi4TvbE0RRzHTHt.tt4oY6', 'LUCIMITH KARINA', 'CORTEZ GONZALES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (332, '42740847', '42740847', '$2y$10$uRzy5aYGWdy1xl42hrzQd.lBLsMYwp90DpS3llULvhfJAu.p3Bvva', 'AGAVIO', 'ALEJANDRO FLORES', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (297, '40230192', '40230192', '$2y$10$Dgn/V.WOQFoWXdAdAgkp3OrZYEsrd.NcDDrURS9.qOtVfuxgkgMd.', 'JUAN JOSE', 'ROJAS HUAMAN', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (335, '43411893', '43411893', '$2y$10$rU6Bdg/FZc0Jeg2ei9fBM.oR4xVT8XikPqR3oMgSd2/xc.umvc/0u', 'ALEX ROLANDO', 'PEÑA BARRIOS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (258, '10601720', '10601720', '$2y$10$IjEllGd229ARCQtNN/WE5eex/ND49QADYuMUcoQEHjWw2RGMfVRUa', 'DARLENI IRENE', 'RIVERA HUAMAN', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (208, '08748177', '08748177', '$2y$10$3xDSzZw4hKbhj9bDzqpBd.ak2fgMJDkoCDtpr5rAalGcYC4hgD8ru', 'PEDRO ANTONIO', 'CHIRINOS HURTADO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (146, '02864824', '02864824', '$2y$10$5VCBWAUu8hW/v.zw1r6YB.xzQEaLq8e4IA3MmRyJaqGIIqpYI.5vK', 'DE LOPEZ MARIANELLA YNES', 'ROSAS TALLEDO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (424, '80228339', '80228339', '$2y$10$xIYe5Pob2KHoAnaDIzrkg.xNHSSdO/Rly9vzn71YB2vD/qCUzkRTK', 'IVAN FLORENCIO', 'DURAN NUÑEZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (249, '10158933', '10158933', '$2y$10$Liw2hhsuzqGlnB4hUJSC8ueLtDZ9G.YfgEEkPCQMaTQJ6ivGCe2uS', 'GODOFREDO VLADIMIRO', 'VALDEZ BLANCO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (334, '43152463', '43152463', '$2y$10$7an09JQ.t2lvwCswsaMmKOCk2tvsxhEWnmHMcR96nKikAsjFjqK/6', 'MARIA MERCEDES', 'SANCHEZ MACHACUAY', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (174, '07321167', '07321167', '$2y$10$1A0c6/JBzeVilQ4e3QNFr.smBejrfnheatycIvfZ1l/Su8QM/wA2e', 'JESUS FRANCISCA', 'CHIONG SAMALVIDES', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (202, '08588546', '08588546', '$2y$10$3ATK1RKCgQf/hNywlTZbjupf1MP5A4TGzQ/FRqvZ6Io3Civ7Yv4OS', 'GAY ALFREDO', 'GOMEZ MARTINEZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (173, '07258554', '07258554', '$2y$10$.gExo7ShOGtJnkURh3boAeql1WaMyQz0RjKccuTZIiT43qyxAgeKO', 'JUAN LIBORIO', 'LOPEZ SALCEDO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (303, '40430676', '40430676', '$2y$10$ckPpz4EuuHfZl7roZTywMuVmPgajnL5DBYFrhi51jVg3XYn03L5Qu', 'ROSSANA EDME', 'NUÑEZ SANCHEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (342, '43921460', '43921460', '$2y$10$6fOG2UVxABnUClll1Jv37eLeyVaEBpRs6con.405akO8CgFhkww/q', 'MERY', 'PANDURO CORAL', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (321, '41779566', '41779566', '$2y$10$vBly1RmROv7YAS.GW4nQFO719VS2.FDXSl4EXvilNU4rhtEMN67vq', 'CYNTHIA GIOVANNA', 'ARREDONDO BELEVAN', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (187, '07633728', '07633728', '$2y$10$8ijCR.gvXtUZZLjP7Uh0BOzlk/C6mdd6ILMhzycY0KGMCCPemv7Ze', 'ELIZABETH LUCIA', 'BALLON NUÑEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (368, '46182687', '46182687', '$2y$10$YOqoBFfUrP8/YVRSWQI.te/UvkOBnlbU9Ok67qOynF5fgFGHWW5q2', 'VLADDIMYR FREDDY', 'OYARDO SUAREZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (254, '10323832', '10323832', '$2y$10$sv6Zka3fczwOazWCxlwLk.yj042v9cgTDkvWEhXzZi3yUZeUIczb2', 'GUBENCIO', 'SILUPU YESQUEN', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (276, '21298781', '21298781', '$2y$10$OOsEDJ.Jxd3tzTZG6HwWQObyMaSBVOaALy9v7Ig7F215boGxSibcW', 'ALEJANDRO MARCIAL', 'PEÑA AGUILAR', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (152, '06248185', '06248185', '$2y$10$sQqK7VrWYF676mLtmhFwZ.J2L77BepAhJ0ufulAV8EBunHBMC8t8K', 'HAYDEE CECILIA VIVIANA', 'FERNANDEZ TAPIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (184, '07535978', '07535978', '$2y$10$tmDnshn62MQ15Zo/UQussuQI9NYC2tQ9lKs21yYOrz37454ywnE9G', 'CARLOS RICARDO', 'LOAYZA OSORIO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (315, '41407980', '41407980', '$2y$10$Z93YnxjsjGzQvCWy7Lfgeu7gT1HdAAn0PqOodC3l30rf0cHsYk/w2', 'OSCAR JUAN CARLOS', 'TATAJE OBERTO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (213, '08877091', '08877091', '$2y$10$icneTIyn8NfPfWy8yMDRcuqx83tp2cgKB9h1nB12.EMhGgAVODay2', 'LUZ AURORA', 'ALVAREZ BETANCOURT', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (445, '41844509', '41844509', '$2y$10$P3o4c1Sr6ZFC/oKKjqSHOuibmHAI18RAexwNMHfJW9waIv7YK4uia', 'NESTOR RICARDO', 'MAMANI ZAPANA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (362, '45814002', '45814002', '$2y$10$mkFukEU9Pgd.cXkp6b43NuH1s4vH3cyacMozHNc4.jxTxfT1IHoQ6', 'MARIANA ESTHER', 'SERNAQUE VELARDE', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (255, '10333768', '10333768', '$2y$10$Tyuc9.wn2DEfcwthd58nouJ1ZJwgS8rUWj3maYtCHvKAS3BBq4Iy2', 'IRENE EVY', 'PAREDES GIRON', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (405, '70652467', '70652467', '$2y$10$lXb39e.d2yxNv8UlknSLzubfXKWew.a.uwl6hVD4.tVghIOkWy.JK', 'EDUARDO RENE', 'ROJAS AMPUERO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (324, '41871076', '41871076', '$2y$10$cfsgz40guX34NLgrOjKq2.OXt0iNB0KqVqV3Jno8Wd1460eUZ9PJe', 'REVELINO NERIO', 'AMANCAY ACOSTA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (195, '07965843', '07965843', '$2y$10$.VOfE5GfcLMEgZdSyHPnkuPC6QXeV2MRLIP7odHw1FB8w8JVU/NVW', 'ROSA ISABEL', 'NINAMANGO BALDEON', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (360, '45558955', '45558955', '$2y$10$67QwCctu6dqXXV9YVp8ML.1hPnr/SOh5.LxkZYZtNb0vqBSf1Y4ii', 'MARTINA', 'RAMON SANCHEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (272, '16721213', '16721213', '$2y$10$93gwNbY4dDgRAUD.4k96zeVRJ4Ji56ry2VnjNkxJlab7quiTr9XE.', 'NORMA ANGELICA', 'MECHATO TELLO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (380, '47165162', '47165162', '$2y$10$flOsRhbAs0bAhq8gBFEmRuLw2vVmEXm801DkDg481kUhn48cIve0a', 'FRANKS', 'PIZARRO MAURICIO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (322, '41815877', '41815877', '$2y$10$Hv.MM7IKI8SxeqKbGGJ3/uZEiwa27w9O.zUG1bMKDax3oEFaWfcle', 'MARIA CYNTHIA', 'LEON CARBAJAL', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (449, '42711745', '42711745', '$2y$10$kyCFyzdx0SEoQknOi9ohbu9MgTdbRma4w.XUXwimc4xAuo4mRUcHy', 'CESAR ARMANDO', 'PEREZ RIVA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (450, '71707769', '71707769', '$2y$10$dvsuZ2oRtBkryPkT5W43gOuPkTlwsPJGZMo02yQYcW/XS6ayvXQaq', 'ELENA MILAGROS', 'RIMAC TELLO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (268, '15747857', '15747857', '$2y$10$P4aVHJOKsGDyBIF1jaa2YeYpZQ5mUblnZvJOO2F7OZa0rt9xMTVf2', 'PATRICIA', 'SIPAN CHILET', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (260, '10695409', '10695409', '$2y$10$cFytRtjs0THTaA.J22YM6.hOg8TH5WYTEoNG0wfxTS9lDCRG7BbJa', 'JENNY', 'MAYURI ESTRADA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (415, '72847973', '72847973', '$2y$10$sPbFGGcdjNjSxDVy.YgkFeAGplCsivbVeDWqvd0CR9Ks6j5BOS9sK', 'MOISES JOSHEP', 'COCHAS GUILLERMO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (383, '47415813', '47415813', '$2y$10$uSUtM86O1NCVq0VcIDcCauRsp04tzkazG92dk.HvMIE/GQudG0UIe', 'MARIA LUISA', 'CASTRO SOUZA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (304, '40535291', '40535291', '$2y$10$Xb0DJV0WWtxXiLHiWRp8Z.Yg4wjmjg6jeVxhw/Z1alTRnjPuklI3C', 'JESSICA MILAGROS', 'MENDOZA GARCIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (341, '43819336', '43819336', '$2y$10$NsLWIMS7FpfoQT7XyL2QWuZhBziluMsiSSfxYPhtsu6be8Lqe.ED.', 'JORGE ARMANDO', 'AGUIRRE TAFUR', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (357, '45310959', '45310959', '$2y$10$7wWwA.byP7giZnADA31n4unV.NM5RS0dI3aTI3cXsx6gCW1Ih8xAa', 'EVELYN', 'CHUNGA REBAZA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (365, '45876850', '45876850', '$2y$10$DfizTCYSPyDh6g0ClHtwVurUpHk4wzN47Ta.9b.EK9ljTHiyIuwSy', 'JAVIER MARTIN', 'CALDERON TRUJILLO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (236, '09610605', '09610605', '$2y$10$o5C.TS9fFMwPG1vwRY2BX.z5ctjk97srr33/rW7pS7gTdgwZniv26', 'VLADIMIR ULUGARDO', 'MARIÑO TENIO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (278, '21554001', '21554001', '$2y$10$Q1vA/GkugUohvpaH5.eDses012sd/RIaqz.EFv5mhBaP.9RdotCWC', 'RICHARD', 'LOPEZ JURO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (402, '70475822', '70475822', '$2y$10$6Ne6g97LbF3PqTs2BaqIMeVGg4F3UCPuyO3hbZfVyQVDVkekellHy', 'MANUEL ENRIQUE', 'RIVAS SUAREZ', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (435, '45650786', '45650786', '$2y$10$BET63lpFGYWFv6tJATxRD.Lr9N74e8/NTpQcv4zGtBEPBOqanpCcG', 'ALONSO RODRIGO', 'ORCADA REYES', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (434, '09446151', '09446151', '$2y$10$48f6yT4NjCJ/Tnm.ZsMh2esx1EVV6TWiMhZQfeZXQJv2HXK4m.vny', 'NELIDA ESPERANZA', 'DIAZ TARAZONA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (441, '46481723', '46481723', '$2y$10$Jryta9ORn5AycDyL0vukLuE.rWtCUDOJfosBxr1VXJCIWNXPn00Tu', 'DAYANA JESSICA IRMA', 'GUEVARA CABRERA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (462, '40348799', '40348799', '$2y$10$zpKSDCIduUe12btUbpYTxOpDGeCuJYhtFvQdhUCUzpN84OgM3TyAG', 'ALEXANDR RUBEN', 'SANCHEZ BUSTAMANTE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (454, '70986608', '70986608', '$2y$10$gH6trU9aKd1q6aBzW9Az/.WHmv8ab0jcxcRUIUCqTe9xSHqEckeWa', 'LESLIE FLOR', 'ZARATE CLAROS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (475, '41109441', '41109441', '$2y$10$XjDmVp79ev25nLIJoIeq0Oj1PBhH6euBHFAlX9MOcVAg4Eb2bZB/K', 'GIOVANNI ALADINO', 'REYES VEGA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (474, '33589617', '33589617', '$2y$10$JsinbkWrNfTZLBcnDMySQ.SsNGiHmuadEkZ0CxVWQH4h861PDLama', 'JOSE MARIA', 'OLIVOS FLORES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (483, '09812120', '09812120', '$2y$10$3GGpzNuday62cxGb5oewQuazIrWtbqs5UgRvo5LyXMlmSF7D7p7Rq', 'UBALDINA GUADALUPE', 'GARAY JURADO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (488, '45325663', '45325663', '$2y$10$/IwIcCijd3HVmmCZvImoT.4GBqitwnjHAMcyGfMEPioW6kua5GoLy', 'ELEN LIZET', 'MARIACA MEINGOCHEA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (504, '40172228', '40172228', '$2y$10$KYKCkucgtqD6bKEDHggRY.23k2EEAe5/F//BtfYXPHxs8YaZzdn12', 'ANGELO NICOLAS', 'PALMA ZAMBRANO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (499, '06771261', '06771261', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARIA OLIVA', 'CHAVEZ UBALDO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (844, '47180915', '47180915', '$2y$10$k4uJvulo8g6UdCMQpsxRN.Ok73OFF66lWzG5bSs.Kwdpw.bBH6b1G', 'GIORGIO ANDREÉ', 'PACARA ASPAJO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (289, '25717592', '25717592', '$2y$10$JNoYDcZXvudww371/jod4OF2UxenrkH7.GKeZU1vfVMh6OlSMNDii', 'LUZ MAGALI', 'AGUILAR SUAREZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (508, '27066311', '27066311', '$2y$10$xBlGb430YcVAcwN4knNek.iMEKXtnl8ZJNyha6N7H4txCEuKqQfxG', 'FERNANDO FRANCISCO', 'VELÁSQUEZ PAZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (511, '45457389', '45457389', '$2y$10$pssKs2Fvoa.vAIeMraxmzOIaE0T4XDTZmYu58QKHBIxcJVR77Hz.u', 'RAUL MARTIN', 'ALVARADO MORENO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (497, '44169652', '44169652', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JUAN PABLO', 'VILLANUEVA FERNANDEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (515, '10710094', '10710094', '$2y$10$83ugsteKQJVrSMfpMcWN3O2LY28/IfZdnU.1G1J1Q4yJyHNLj.GYm', 'HERNAN', 'HUIZA BARRUETA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (309, '40773408', '40773408', '$2y$10$dUJ2d6xvrtIAUfjhTENSY.ugy.ILvllXo6YJYW8z/R2ZBx4.8dTzW', 'WILLY KLEVER', 'DAGA SARAVIA', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (503, '06576500', '06576500', '$2y$10$k1WVD2KgkoB56CEOmClpPekNLbI5nn3/G73PnVs80OYwS./CBJhCG', 'FIDEL', 'CÓRDOVA SAAVEDRA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (516, '46932368', '46932368', '$2y$10$AgcHjrB/BYbwb2v/T7LIy.LLaFB2209t/nWeuqebGNM2vv715LjYi', 'CARLOS ALBERTO', 'NAJARRO MEJIA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (486, '72185747', '72185747', '$2y$10$79EYlo/vC7MWVS/obloHsemsxX7ymkKtnmKhgqqZyavQRLbKFzKqy', 'BERNAL JOAO ISRAEL', 'LA CRUZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (401, '70439050', '70439050', '$2y$10$IauCBjWJfKKyVU1mgVMZpeWn9HamsY9R3bAKuTJWwiBGXYGLtsGBS', 'GIANCARLOS', 'MIRANDA CASTRO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (501, '06812970', '06812970', '$2y$10$IH4zGnQCTHKc/dKMNfogyOP/eu7AkSUTSijXqc.eqRFYtuztXEpv.', 'DAVID EDUARDO', 'GATILLON REJAS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (523, '44116227', '44116227', '$2y$10$rJscHsGAr.Niw.FyePtqQumyUalzo/mnfno9SgpDdvZYMT/qka3.K', 'GUSTAVO ALEXANDER', 'CHUCHON CUTIPA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (467, '40621292', '40621292', '$2y$10$0EvmUq7PLnHwAoUfYDVpZuiS6pKMQGkmI9oVGqrH0Tj3E4CDPbeMG', 'SARA ISABEL', 'MERLO RODRIGUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (417, '74121511', '74121511', '$2y$10$k1b/pOBZoUhGb9Q0GehrWOKVSoTAm54PvkunM3x8RVVLZtNcjBdTC', 'MILAGROS YRAIDA', 'TICSE GARCIA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (296, '40128857', '40128857', '$2y$10$xY0ShOyhSzxp96HxffFDMe3iMYKiOj0fd/U2J/IOCGBMSjtibkpM.', 'GINO GIOVANI', 'MENDOZA ARROYO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (522, '06733569', '06733569', '$2y$10$X4JzS7yk7rqeilRaQYEK1uuQz/JMzkVpQGs4i5YsmkjqloQ2FtyYO', 'CARLOS JOEL', 'YSLA LOZANO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (547, '47103463', '47103463', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARIANELLA', 'HUANACCHIRE MAYHUIRE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (549, '47219578', '47219578', '$2y$10$A8IHgMBlKV6O2fzeGasSoebma34evFocIbPlAcvw2fsOKqfN.S7Gi', 'BHEKY NOHEMÍ', 'CASTILLO PICON', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (557, '41077438', '41077438', '$2y$10$jC.H.NsZ6fmqKxf.Y7KX1.vVXQXe7ydw9bXe9H/N.609ZqgqkYGNq', 'DANIEL ALCIDES', 'VILLARREAL VASQUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (558, '06765745', '06765745', '$2y$10$.PbejqWT999TS3k8iEeFlOb7f/GH.xmNYkA6HrBvrHqWYWeyg7uze', 'ENRIQUE MANUEL', 'ESPINO VASQUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (126, '09804238', '09804238', '$2y$10$ZeBMwrFTmz6kydJfW6I1RO9LUXzPNSOQAUcTGf1AyWoTVCqtLp9Ia', 'WHALTER', 'BARRIENTOS LOPEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (578, '44908699', '44908699', '$2y$10$cv.ndyNRy/t4TrCAS9ChhuAb5BQDanUsdcc4yE84H39vGrKAPB24y', 'ALEXANDRA RAQUEL', 'BEROLLA ORTIZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (599, '43442148', '43442148', '$2y$10$FlyQKQG3akxTveEAZnMWd.2E88sQxkkYY9EZCKgYxDQiNJCxqM9/y', 'JOSE MIGUEL', 'MAURICIO SOTO', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (641, '40597144', '40597144', '$2y$10$U.GaoWpm1UjGUU/qRenKe.dVJ4ngGk9v9tmzi9nZBYCVHywSgigA.', 'WALTER ENRIQUE', 'ROCA SALAS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (343, '44064295', '44064295', '$2y$10$AChu0XpgJeHkaaZTHjf27uSYr3i8ONYtE0TQGxSyHiK30Z45KB8MW', 'CARLOS IGNACIO', 'MERINO ROSAS', 'M', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (636, '46955610', '46955610', '$2y$10$As.25eQLwJNrUMgxb06MBug9rojjAehNLgJEt1s3w1YEVZXft69zO', 'NELLY CRISTINA', 'MONTALVAN GOMEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (654, '43223849', '43223849', '$2y$10$2SpLewNPEfO2HULNSUp0QOLl59yFBTBfUxYxpNw8tJ0kvO0k24Ri.', 'WILLIAM', 'PACHAS GUTIERREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (681, '44695322', '44695322', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GERALDINE', 'YALTA ZUTA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (674, '41674402', '41674402', '$2y$10$PzH58dSOJjcaSbSSBQlOVOPSg8lIsU9FpJ93bJ0FiJMRVHQ7/uaKi', 'BERONICA OLINDA', 'CUELLAR CORNELIO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (692, '76587651', '76587651', '$2y$10$rU6Bdg/FZc0Jeg2ei9fBM.oR4xVT8XikPqR3oMgSd2/xc.umvc/0u', 'GRACIELA', 'THUPA VELASQUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (694, '70686595', '70686595', '$2y$10$o5iufEqQEN0p1v.jWUVkq.8IgpJC90yda6OI68hF099wxwzHKBK1u', 'ERICKA DANITZA', 'SOSA VARGAS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (726, '45585785', '45585785', '$2y$10$lp3GcotDgcFvJDRcgt6cjeaX5PJwbEuCkR9b7kHSh/iqkwmMqLEZe', 'JUAN DIEGO', 'MORENO RAMIREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (827, '76796471', '76796471', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'KIARA SEREYNA', 'ROMAN PELAEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (867, '09884347', '09884347', '$2y$10$Ds/iqJKJc0EVhL4b2KE.z.ZwUuCEwYGsRrJBeVAUXaOwjPRkQy3.G', 'NORMA ELIZABETH', 'CARDEÑA DOLORIER', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (874, '44218683', '44218683', '$2y$10$xKHRxaSkvxYO9YJU7toMhOsYqrgCD3ltCLxSx2c80DHby9M60royK', 'EVELYN JACKELINE', 'NUÑEZ GOMEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (863, '17810780', '17810780', '$2y$10$vmufDqGDtBzWdjc6C7/qLOG8CVxcY2X7SkdRsn4O8zweOuxfgKzXm', 'YSABEL DORIS', 'PAREDES DAVILA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (861, '08632602', '08632602', '$2y$10$kd0iCz8bWNMM2d98VHyUJ.oRmQhXavPWb./wfmW6cJ6eSlcPfHzgy', 'NELIDA', 'ALBINO IGREDA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (860, '07679171', '07679171', '$2y$10$n7rQTN6LFPDgUZ1BkgzG5OMsspXb/8cVV9Mh/R40zRMdHIsAD9rAG', 'JUAN ALBERTO', 'QUISPE SOLANO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (869, '40707423', '40707423', '$2y$10$8KrgSiBevcq3fd8l.7n5IOxYVvyBlYuCFoCNCJCHq3gAsAW6xELJC', 'WALTER GROVER', 'GONZALES RAMOS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (695, '21485385', '21485385', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARTHA', 'ESPINO UCHUYA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (823, '09614257', '09614257', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CARMEN ROSARIO', 'MENDOZA HUAMANI', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (877, '40596246', '40596246', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GONZALES CARMEN DEL PILAR', 'LA ROSA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (878, '09429379', '09429379', '$2y$10$Pufm2y6aWU1YqoJMsTUxMuAZlNjTkPldi12yUPw16rXrD1QBxLsp2', 'LUCIA MILAGROS', 'LOYOLA HILARIO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (327, '42214806', '42214806', '$2y$10$uLPfsZpiImPutbBw2GjrGuTD2btQ/APCpEx9KUuGeVGA0NvR9FEXy', 'ANA MARIA DEL ROSARIO', 'REYES MENDOZA', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (688, '07453098', '07453098', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ELIZABETH RAQUEL', 'FLORES HUAMAN', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (758, '09923319', '09923319', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'PEDRO ALBERTO', 'GARAY BAILETTI', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (822, '42305719', '42305719', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SAUL', 'BELTRÁN PETREL', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (834, '07758977', '07758977', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'LAMA VICTOR HUGO', 'RAMIREZ DE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (838, '07443911', '07443911', '$2y$10$ww.70PcHwNTDVBP4VohqpO37hwEnbO/AOR7kfz.yNjhq5YKzjg/ee', 'ENRIQUE EDGAR', 'VILLANUEVA CACERES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (882, '75521297', '75521297', '$2y$10$am7NocTYFFXoBnzBBBjau.Fkv9hi9gqbAXv/m09nfZpnipzG/Sa5S', 'AMADA NOEMI', 'ESPINOZA ANDAMAYO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (884, '45846678', '45846678', '$2y$10$dGzpMiNqjEbdLHw1sibvsenBZr065U9vI6ZRxJMumfcWn5Nl6/Laa', 'WILLIAM FILEMON', 'LEON ALLCA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (888, '76770588', '76770588', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'KIMBERLY', 'FIGUEROA AGUILAR', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (892, '42074480', '42074480', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'FREHLY ROLANDO', 'SOTOMAYOR FERRO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (896, '07520981', '07520981', '$2y$10$c5zxH7oe1EJw7kjmKuhEwOkZ9KGywScpzrFgE6Ha5bn4UraopFKKe', 'FRANCISCO', 'VILLALOBOS GONZALES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (897, '27375169', '27375169', '$2y$10$4s2HM31bIeR845se2mL5AuFZEZs1ZB99UWcuDAbsKVqad.VVWNP8O', 'JORGE', 'SALAZAR PERALTA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (901, '44537544', '44537544', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SISI ORNELA', 'ARANDA MATAMOROS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (906, '10688013', '10688013', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ESMERALDA ICHA', 'ESPIRITU ORELLANA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (912, '10389734', '10389734', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'KARIN', 'PEREZ PAUCAR', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (913, '45242473', '45242473', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JESSENIA ESTHER', 'CUTIPA CHICOMA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (914, '40415709', '40415709', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ELIZABETH', 'ZAIRA HUAMAN', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (920, '42561852', '42561852', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CARLA PIERINA', 'CALVERA LUJAN', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (921, '06269714', '06269714', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'BEATRIZ YOLANDA', 'TRUJILLO SILVA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (979, '09673394', '09673394', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'RUBEN SANTIAGO', 'VILLARREAL MOLINA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (924, '75544839', '75544839', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'WENNY SHAKIRA', 'CAILLAHUA LOPEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (926, '17450890', '17450890', '$2y$10$U5TSuB10gNrkTcw55yWfMu0DHkBWln2g/LeYQysUzFD/.aV3JU2ae', 'JAIR ROBERTO', 'SAMANIEGO ORDOÑEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (927, '10064633', '10064633', '$2y$10$TIrM9cI4i5khLl.IaTSsYu7fIy3UZeGdMROix9QTA96Q.MIjLnn7G', 'MARVIN GERALD', 'ALTAMIRANO CAMACHO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (929, '40991461', '40991461', '$2y$10$p0numbmmg0SZhAtFwL3WKua8xqHTyrXCPeOoz2xJu601ippuJ/P7K', 'SERGIO ALEJANDRO', 'MANRIQUE ARRESE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (930, '70105979', '70105979', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CINTHYA', 'ZELAYA CHAVEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (937, '09604638', '09604638', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'WALDIR ROMULO', 'MORA CORONADO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (938, '07245255', '07245255', '$2y$10$w.wwI4p8VdfW2IU0xvc8v.dTgaKQaa0scuWXuz59wJpXY.XDqu5B2', 'LUCY ANA', 'VASQUEZ ALIAGA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (940, '48486497', '48486497', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GRECIA', 'VILLAFUERTE LUNA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (948, '06901612', '06901612', '$2y$10$ZFW2U7Zt4qGQwwOkIADiQe85O/mWoThIaHlxz0aGHvyOvXX1sUMla', 'CESAR RICARDO', 'RUEDA VICENTE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (953, '43273501', '43273501', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'VICKY LISSETTE', 'GONZALES BELLOTA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (959, '25583871', '25583871', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARIO ALFREDO', 'BARRIAL MORALES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (955, '06731563', '06731563', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ANGELA MARIA', 'RAFAEL POMA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (963, '46790566', '46790566', '$2y$10$h6UhZL7PgD6kT3/b.3rr8.8rLAh5fsME791k24rPuuNcg/zS3UHLa', 'OSCAR EDUARDO', 'MEZA TINOCO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (978, '42213740', '42213740', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JENNER', 'TEJADA CORREA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (977, '41391953', '41391953', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DIEGO ARMANDO', 'ROJAS MAURICIO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1038, '21856987', '21856987', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JORGE LUIS', 'CANELO PORTILLA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (997, '45510149', '45510149', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'WILLIAMS FABIO', 'SALAZAR ALVAREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1037, '40201014', '40201014', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CESAR ROLANDO', 'HERRERA ROJAS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (999, '43733364', '43733364', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MIGUEL ANGEL', 'TOCTO FLORES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1002, '07377983', '07377983', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'HERNAN TEODORO', 'ARZAPALO VALLADARES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1036, '42798362', '42798362', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'LUIS IVAN', 'MESTAS RUIZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1005, '08429775', '08429775', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MIGUEL ANGEL', 'ROSSINELLI GARCIA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1011, '07706838', '07706838', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARCO TULIO', 'PACHAS GOMEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1033, '06767517', '06767517', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CESAR AUGUSTO', 'BERNAL SALAZAR', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1019, '10135998', '10135998', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARIA LILIANA', 'TORRES PRADA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1018, '73697605', '73697605', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'OMAR ESGARDO', 'GARCIA PINTADO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1031, '40732523', '40732523', '$2y$10$gZBcSE8Cp4pZ.9Oy7j7ADe6ywcT9HFrYgl0InLRXW7Ji1BgSVjZWu', 'KATTY SUSANA', 'MORALES OSORIO', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1080, '02848235', '02848235', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'EDUARDO ARBEL', 'VILELA DIOSES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1030, '47736758', '47736758', '$2y$10$paLLqYf9CPc60biUnjMxl.fzK/e.ums9NYPQlE.UCN8buhIZWebES', 'JENIFFER JULISSA', 'COLLAZOS DOMINGUEZ', 'F', 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1040, '45758143', '45758143', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'PAOLA ANDREA', 'CALDERON BENITO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1121, '42157098', '42157098', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GIANNA MARY ANGGIE', 'RONCAL COZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1048, '45204260', '45204260', '$2y$10$LSQXa4L16VlxATITWruNkOowSu0ejzPhraGccnHWESnRpSkF.fwfa', 'JENNIFER SUSANA', 'ARMAS REZA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1120, '07717254', '07717254', '$2y$10$CWFmQXY2fAM9ynXxO57zNuq7kUa50x/PLYJDoG1XhCF3u83.Ygj.y', 'CONCEVIDO BONCONCLE', 'BENAVIDES RUIZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1052, '42687859', '42687859', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MIGUEL ANGEL', 'MEJIA ALFARO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1055, '47394322', '47394322', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JHON JAIRO', 'MALQUI CHUQUIPIONDO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1118, '09719335', '09719335', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'LUZ RAQUEL', 'RIVAS PADILLA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1226, '10280514', '10280514', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'BLANCA MONICA', 'CORDOVA DOMINGUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1117, '18143619', '18143619', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GISELLA PILAR', 'GARCIA MONCADA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1116, '70091384', '70091384', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ANDREA FIORELLA', 'GARCIA BANCAYAN', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1079, '16759114', '16759114', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'HENRRY CRONSWELT', 'TORRES CUSMAN', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1090, '44645355', '44645355', '$2y$10$NW2SB4TBLYsrgQ67r7HyWuZOXHgWEf8h6ESn4VGbbYHYj2GbKaR62', 'EMPERATRIZ', 'VALDERRAMA CRUZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1094, '07176195', '07176195', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JOSE MARCIAL', 'AGREDA BERROCAL', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1096, '09941664', '09941664', '$2y$10$56DmzHTLsubAztyYIsUQlubasheCwZjaCCBX5n/oZn24GcqXIZEp6', 'HALDANTH LESTER', 'CASTILLO URDAY', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1097, '10793024', '10793024', '$2y$10$tllLTBMrcsOiHUATzYP...yQmLXOQOgUu/ETEnNx4b6YnvnJM/1R6', 'SILVIA SUSANA', 'GUERRA GUTIERREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1100, '41184465', '41184465', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'PAUL JOSEPH', 'SANDOVAL ALVARADO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1114, '45490015', '45490015', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'WILIAMS ALEXANDERS', 'TIPISMANA CARRILLO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1103, '45026380', '45026380', '$2y$10$ZefffMa/hsSGM1etUpIb3eSp4hUoPn5.lmg2WsnoCilhNjEnd3ny2', 'VERONIKA SOCORRO', 'QUIQUIA SUAREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1105, '71324383', '71324383', '$2y$10$geMHYRmH9oeA4w0AjI3D/.Bxb5ylc5J1RpcCmq.ysEbRGePhNE5r.', 'CLAUDIA LIZBETH', 'BARRIENTOS DIAZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1106, '40529207', '40529207', '$2y$10$J4hor5zH/Nn2aGMCjA2EXeBUSmpijxZNhKXh/RW/Qbs.Fk399e/6e', 'PATRICIA MAGALY', 'VILDOSO RAMOS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1107, '43559425', '43559425', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'URLENI', 'LEON FERRO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1113, '72177647', '72177647', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'VARINIA ISABEL', 'BOCANEGRA IBAÑEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1110, '10618054', '10618054', '$2y$10$vIm4JErVduIOnJEV4/a0su.DgvTWVZjZor4XVgk/s6gt5V2dv1NiW', 'GIANNINA PAOLA', 'MENDEZ RUIZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1112, '20725298', '20725298', '$2y$10$3HQGiRREmIApkWEGmKzQnucZYTCir1sq5GCm9zyv6yQNeZ6XJVLAm', 'PERCY PAUL', 'SALAS MORALES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1125, '09763070', '09763070', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CARMEN LUCIA', 'APAZA YANAC', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1128, '47174388', '47174388', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DE GALDO DAISY BELEN', 'BERNEDO TAPIA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1225, '09187347', '09187347', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GLORIA ADITA', 'VILLEGAS VILLAGOMEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1131, '46993554', '46993554', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'KARLA', 'AREVALO VARGAS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1132, '09545551', '09545551', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ALICIA JEANNINE', 'LAMAS ABANTO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1137, '25847969', '25847969', '$2y$10$73wznUTGbHeMgrURIpnGg.5unK5y2DBTjgXQpKrA4G.Y3tTnHOTQS', 'MILAGROS PAOLA', 'NIETO SANCHEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1143, '43635711', '43635711', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JESUS SOLON', 'TELLO PORTILLA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1224, '72840707', '72840707', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SEBASTIAN ODARIS', 'HIJUELA QUEREVALU', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1145, '07625320', '07625320', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'RAFAEL INDALECIO', 'GARCIA RAMIREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1146, '40247525', '40247525', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DAVID MOISES', 'SOTOMAYOR ROSALES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1147, '40743120', '40743120', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DEYANIRA', 'VALERIO PALACIN', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1153, '07571457', '07571457', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GUILLERMO CESAR', 'FIGUEROA ASENJO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1154, '70000999', '70000999', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CHRISTIAN FABRIZIO', 'MURGA VILLANUEVA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1155, '00829799', '00829799', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARTHA ELENA', 'ANGULO VASQUEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1156, '42644753', '42644753', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JULIO CESAR', 'LEON QUISPE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1157, '43109171', '43109171', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ALAIN ANTHONI', 'MONTOYA CASTAÑEDA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1222, '09596950', '09596950', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JUAN GABINO', 'WATANABE BALLARTA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1160, '47527370', '47527370', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MILAGROS ROSANNA', 'RIVERO UPIACHIHUA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1161, '43487913', '43487913', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MILLY SOLEDAD', 'PALOMINO GUTIERREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1162, '70674175', '70674175', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ROSA RAQUEL', 'JAVIER JIMENEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1221, '02756431', '02756431', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JOSE RICHARD', 'BASTO PARADA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1166, '47943395', '47943395', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CELENY JASMIN', 'EUNOFRE MALPARTIDA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1167, '46782938', '46782938', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CRISTINA', 'CONTRERAS AGUIRRE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1168, '08155409', '08155409', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'LESLIE CAROLA', 'HUAMAN JAIMES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1170, '04073179', '04073179', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ZORAIDA', 'CONDOR REYES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1173, '21575259', '21575259', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ELIZABETH CECILIA', 'PONCE MUÑANTE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1174, '40946280', '40946280', '$2y$10$LCHekx7tP18pnaQRpZDxB.RzAA2XWkKoD3.dluRgZkhrQhSzmkq8O', 'EMILIO GIOVANNI', 'SCHIAPPACASSE BRIONES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1175, '09324185', '09324185', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GEDOR ELIM', 'GARCIA ALAMO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1176, '25745040', '25745040', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MILAGROS', 'HIGA MIYASHIRO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1177, '41115356', '41115356', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'RUBEN DARIO', 'MEDER RAMIREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1178, '08048697', '08048697', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ADA MARIA LILLY', 'ARANGUREN CARBAJAL', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1179, '22407181', '22407181', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ACOSTA MARGOT MAGDALENA', 'GONZALEZ Y', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1180, '42935639', '42935639', '$2y$10$TG8zw4mmdF51rzVq/DfWAeCw6w5qlXoxKii7QPe5KS8/8olye4atO', 'CAROLINA BEATRIZ', 'PANDO MONTEZA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1181, '07525424', '07525424', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MILAGRITOS DEL ROSARIO', 'CALDERON ZAPATA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1185, '09521009', '09521009', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ROMMEL', 'TERAN TACO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1186, '44974210', '44974210', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CHRISTIAN JIMMY', 'ACOSTA RIOS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1187, '48065606', '48065606', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ROBERTO', 'CUEVA SALGADO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1188, '70931074', '70931074', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JHOANI LIZBETH', 'VILELA PARIONA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1189, '72313943 ', '72313943 ', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DIEGO EDUARDO', 'MARTINEZ CALDERON', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1190, '75459989', '75459989', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'NICOLN', 'SANCHEZ GILES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1191, '46751827', '46751827', '$2y$10$.yjQVbT0WQtP2svxdQDGFeT5IunkHY60hHax4XZlnRO3l57MLHqrG', 'ADELFA', 'GONZALES MOLINA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1218, '44497729', '44497729', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'WILFREDO LIZARDO', 'CRISPIN SEVILLANO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1220, '06033641', '06033641', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ALEJANDRO', 'RAMIREZ RAMIREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1196, '47785818', '47785818', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SHIRLEY VANESSA', 'LOJA BALLADARES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1197, '44366577', '44366577', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ELENA PATRICIA', 'CASTILLO ESPARZA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1199, '10154986', '10154986', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'PATRICIA', 'CARBAJAL CHAVEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1200, '70490013', '70490013', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'RENZO MIGUEL', 'DIAZ PALOMINO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1201, '74717725', '74717725', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'FABIOLA STEPHANIE', 'PALOMINO AGUILAR', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1204, '48047917', '48047917', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'IVONNE DE MILAGROS', 'AQUINO SEVILLANO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1205, '47571305', '47571305', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ROXANA', 'MORENO PRADO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1206, '72173319', '72173319', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'FELIX MIGUEL ALONSO', 'YAILE DIAZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1207, '73644022', '73644022', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GERALDINE YARITZA', 'PALOMINO DIAZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1208, '72865828', '72865828', '$2y$10$e9mohvv/lvjYUPKPOqnv8eNwkKGoahrlY/Btwf5wA72wgAXcse3uK', 'ALISSON MARIA', 'LEON CHAVEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1209, '71062179', '71062179', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JUDITH ROCIO', 'OLIVAS ESCALANTE', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1210, '72463513', '72463513', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DIEGO ALEXANDER', 'PORTILLA MORALES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1211, '72214877', '72214877', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SAIM OMAR', 'LEON LEGUIA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1212, '71814034', '71814034', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'KARLA APRIL', 'FLORES PALACIOS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1216, '19986696', '19986696', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SEGUNDO ARTURO', 'BAZAN SERPA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1227, '73027191', '73027191', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'CAROLINA INES', 'GUTIERREZ JUAREZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1229, '41517547', '41517547', '$2y$10$NtcyPeRdxuIY.oIMfnEMkOxZO7sFGBeUAKyZL/9B8vF5TpXuEyBh.', 'HECTOR JHONNY', 'ARIAS CAMPOS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1230, '09800861', '09800861', '$2y$10$7r5C9BLrB/vI2b3Pz8pPq.XO3C/aDNzkNIZ9dlLEbNC7uqfbTCIwm', 'JUDITH INGRID', 'CHAUCA SARAVA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1231, '09537089', '09537089', '$2y$10$CTq0Sc51x.qOX5AKCNwOb.4MAMwJYHmkjJqQKLaWvfv2IGKyQmhuW', 'FERNANDO', 'ORTEGA CADILLO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1232, '45119011', '45119011', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JESUS', 'HUAYHUAMEZA QUINCHO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1233, '01345825', '01345825', '$2y$10$k8uHFdsAQnt2zRe86v6gUeM.uYvpcMsiJB8vT7S.ve2MNCvm/ST2q', 'NINFA', 'BAUTISTA RAMOS', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1234, '71038947', '71038947', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'SEGUNDO JUNIOR', 'ALVARADO ESTRADA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1235, '48290284', '48290284', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GRETEL YANIRA', 'COLQUE LOPEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1236, '47105457', '47105457', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'EDITH AURORA', 'PANDURO ARANDA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1237, '40705711', '40705711', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'PRADO ROLY HUMBERTO', 'GUTARRA DEL', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1238, '75156026', '75156026', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'GREYSSI YAZMIN', 'GUTIERREZ DURAND', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1239, '72364552', '72364552', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'TORRE DIEGO ALONSO', 'NAVARRO LA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1240, '40162357', '40162357', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARUJA LIDIA', 'TIPULA TIPULA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1241, '06148237', '06148237', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MARIA TERESA', 'FERRER SALAVERRY', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1242, '08704394', '08704394', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ANA MARLEN', 'BRAVO MARTINEZ', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1243, '70435444', '70435444', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'ROCIO DEL PILAR', 'HURTADO MOLINA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1244, '40252120', '40252120', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'MIGUEL FERNANDO', 'ESCALANTE ANGULO', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1245, '43909143', '43909143', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'JORGE AARON', 'FLORES LINARES', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1246, '73930719', '73930719', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'FIORELLA LIZET', 'CORONADO ESPINOZA', NULL, 1, CURRENT_TIMESTAMP);
INSERT INTO users (id, dni, email, password, nombre, apellidos, genero, estado, created_at) 
VALUES (1247, '09281649', '09281649', '$2y$10$RCRWHv9y6z18N3bjLqTHJ.cyMsPrK56E3WtjcftrSSB1jNz/qZxR2', 'DEMETRIO', 'CCESA RAYME', NULL, 1, CURRENT_TIMESTAMP);

-- INSERT statements para tabla jobassignments
-- Generado automáticamente desde tb_usuario_local.csv

INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'ESPECIALISTA EN FINANZAS', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'JEFATURA', '1988-11-02', NULL, 193, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SECRETARIA', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA', '2012-10-10', NULL, 310, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'ESPECIALISTA EN PLANEAMIENTO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'PLANEAMIENTO Y PRESUPUESTO', '2005-08-01', NULL, 166, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION PRIMARIA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 292, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION SECUNDARIA EN MATEMATICA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2017-02-13', NULL, 237, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA DE EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2018-09-21', NULL, 188, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'ANALISTA PAD', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'TECNOLOGIA DE LA INFORMACION', '2011-12-28', NULL, 246, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPCIALISTA EN EDUCACION PRIMARIA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 291, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'ASISTENTA SOCIAL', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '1981-06-01', NULL, 224, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2014-06-02', NULL, 229, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'JEFATURA', '2021-10-27', NULL, 584, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '1981-08-11', NULL, 163, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'TESORERIA', '2016-01-01', NULL, 290, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE PLANIFICACION Y PRESUPUESTO', '', '2024-01-01', NULL, 870, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '1987-07-19', NULL, 428, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OPERADOR PAD', 'ÁREA DE ADMINISTRACIÓN', 'TESORERIA', '1983-06-08', NULL, 169, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'CONTABILIDAD', '2005-08-01', NULL, 147, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '1982-03-01', NULL, 242, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '1983-04-04', NULL, 178, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'ESTADISTICO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'ESTADISTICA Y MONITOREO', '2006-03-01', NULL, 182, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA DE EDUCACION EN INICIAL', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2019-02-01', NULL, 183, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2015-06-19', NULL, 420, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES - PAGADURIA', '1979-04-01', NULL, 177, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ESTADISTICO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'ESTADISTICA Y MONITOREO', '2013-01-03', NULL, 160, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2005-08-01', NULL, 197, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ESPECIALISTA DE RACIONALIZACIÓN', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2023-09-08', NULL, 791, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES - PAGADURIA', '1988-06-01', NULL, 150, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION SECUNDARIA HISTORIA GEOGRAFIA - ECONOMIA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 227, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES - PAGADURIA', '1983-06-08', NULL, 427, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', 'JEFATURA', '2019-03-11', NULL, 353, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA DE EDUCACION EN ED. FISICA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2019-02-01', NULL, 192, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'CHOFER', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2006-03-01', NULL, 261, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'SECRETARIA', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES', '2024-01-01', NULL, 873, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2019-03-11', NULL, 333, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TESORERO', 'ÁREA DE ADMINISTRACIÓN', 'TESORERIA', '2006-03-01', NULL, 267, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '1987-05-27', NULL, 167, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2022-02-23', NULL, 604, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '1984-12-13', NULL, 159, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'SECRETARIA', 'ÓRGANO DE DIRECCIÓN', 'COMUNICACIÓN Y PARTICIPACION', '2022-02-21', NULL, 632, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ABOGADO', 'ÁREA DE ASESORÍA JURÍDICA', '', '2022-02-21', NULL, 633, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP', 'DIRECTORA DE UGEL.03', 'ÓRGANO DE DIRECCIÓN', 'JEFATURA', '2022-06-01', NULL, 634, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '1986-10-03', NULL, 221, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION SECUNDARIA EN MATEMATICA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 240, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '1986-07-09', NULL, 158, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION SECUNDARIA EN COMUNICACIÓN', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 214, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'SECRETARIA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2022-08-22', NULL, 638, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2016-01-01', NULL, 364, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'CONTADOR', 'ÁREA DE ADMINISTRACIÓN', 'CONTABILIDAD', '2016-09-23', NULL, 186, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'CHOFER', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2018-01-02', NULL, 218, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'ESPECIALISTA DE PERSONAL', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '1987-11-01', NULL, 439, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION ESPECIAL', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2019-02-01', NULL, 263, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '1984-08-31', NULL, 151, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'PERIODISTA', 'ÓRGANO DE DIRECCIÓN', 'COMUNICACIÓN Y PARTICIPACION', '2013-01-03', NULL, 225, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', '', '2022-08-22', NULL, 640, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '1983-04-25', NULL, 179, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'TESORERIA', '1976-06-25', NULL, 204, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2017-10-10', NULL, 326, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TRABAJADOR DE SERVICIO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2018-01-02', NULL, 282, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'SECRETARIA', 'ÁRAE DE PLANIFICACION Y PRESUPUESTO', '', '2024-01-01', NULL, 872, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION PRIMARIA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 200, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'ESTADISTICA Y MONITOREO', '2022-02-21', NULL, 602, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ESPECIALISTA ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES', '2022-10-19', NULL, 644, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '1978-11-16', NULL, 287, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION PRIMARIA', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 277, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '1984-07-01', NULL, 176, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP', 'AUDITOR', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2023-08-18', NULL, 789, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'CONTABILIDAD', '1987-05-30', NULL, 293, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION INICIAL', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 194, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '1983-06-08', NULL, 157, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION SECUNDARIA EN COMUNICACIÓN', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-02-13', NULL, 180, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'OFICINISTA', 'ÁREA DE ASESORÍA JURÍDICA', 'ASUNTOS ADMINISTRATIVOS', '1987-08-06', NULL, 207, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '1982-11-30', NULL, 217, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN SUPERVISION', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SOPORTE AL SERVICIO EDUCATIVO', '2015-08-10', NULL, 209, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SUPERVISION DE IIEE - PRIVADAS', '2014-12-04', NULL, 314, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2014-09-16', NULL, 384, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '2016-06-01', NULL, 185, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE ASESORÍA JURÍDICA', 'ASUNTOS ADMINISTRATIVOS', '2014-06-02', NULL, 320, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'JEFATURA', '2015-06-19', NULL, 386, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'PLANEAMIENTO Y PRESUPUESTO', '2014-06-02', NULL, 313, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO LEGAL', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2016-06-01', NULL, 301, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2016-07-01', NULL, 149, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2015-07-01', NULL, 306, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2016-06-01', NULL, 444, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ASESORÍA JURÍDICA', 'ASUNTOS ADMINISTRATIVOS', '1890-01-01', NULL, 239, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2016-06-03', NULL, 300, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE TECNICO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2015-08-03', NULL, 411, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÓRGANO DE DIRECCIÓN', 'DIRECCION', '2016-10-13', NULL, 340, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SOPORTE AL SERVICIO EDUCATIVO (SIAGIE)', '2017-02-09', NULL, 318, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL', 'ÁREA DE PLANIFICACION Y PRESUPUESTO', 'JEFATURA', '2015-07-01', NULL, 358, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'JEFE - ESPECIALISTA EN SUPERVISION', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'JEFATURA', '1890-01-01', NULL, 256, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2018-04-20', NULL, 421, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE TECNICO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SUPERVISION DE IIEE´S.', '2016-05-16', NULL, 257, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ORIENTADOR - TECNICO ADMINISTRATIVO II', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2014-07-30', NULL, 155, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SECRETARIA', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2014-07-30', NULL, 393, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN CONTRATACIONES', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2014-12-04', NULL, 275, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2015-07-01', NULL, 191, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SUPERVISION DE IIEE´S.', '1890-01-01', NULL, 252, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SOPORTE AL SERVICIO EDUCATIVO (SIAGIE)', '2017-02-09', NULL, 156, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2014-07-30', NULL, 271, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÓRGANO DE DIRECCIÓN', 'CPPADD', '2015-07-01', NULL, 262, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO 3 -RECEPCION DE EXPEDIENTES', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2015-10-05', NULL, 416, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2015-10-05', NULL, 359, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2017-06-12', NULL, 170, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2015-10-05', NULL, 345, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL LEGAL', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA', '2015-10-05', NULL, 274, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN INFORMATICA', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'TECNOLOGIA DE LA INFORMACION', '2019-06-04', NULL, 347, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ADMINISTRADOR EN REDES Y SOPORTE', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'TECNOLOGIA DE LA INFORMACION', '2015-10-05', NULL, 144, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'JEFATURA', '2015-10-06', NULL, 377, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'JEFATURA', '2015-10-05', NULL, 381, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN INFRAESTRUCTURA Y MANTENIMIENTO PREVENTIVO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SUPERVISION DE IIEE´S.', '2015-10-05', NULL, 198, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2015-10-05', NULL, 265, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÓRGANO DE DIRECCIÓN', 'COMUNICACIÓN Y PARTICIPACION', '2015-10-12', NULL, 302, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'PLANEAMIENTO Y PRESUPUESTO', '2015-10-12', NULL, 238, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2015-12-01', NULL, 361, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2015-12-01', NULL, 308, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2015-12-01', NULL, 234, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2015-12-01', NULL, 339, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2016-03-03', NULL, 307, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ESCALAFON', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2016-06-09', NULL, 376, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2018-03-01', NULL, 407, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2016-03-11', NULL, 311, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN SELECCIÓN DE PERSONAL', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA', '2016-06-09', NULL, 323, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA II', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2016-06-27', NULL, 189, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN RACIONALIZACION', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'RACIONALIZACION Y MEJORA CONTINUA', '2016-07-01', NULL, 397, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2020-12-15', NULL, 325, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO I', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '1890-01-01', NULL, 244, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA DE INFRAESTRUCTURA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SUPERVISION DE IIEE´S.', '2016-07-12', NULL, 226, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN GESTION DE RECURSOS HUMANOS', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '2016-07-06', NULL, 243, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2016-07-15', NULL, 422, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SOPORTE TECNICO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'JEFATURA', '2017-02-09', NULL, 219, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '2017-02-07', NULL, 369, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'EQUIPO ADMINISTRACIÓN DE PERSONAL', '2005-01-03', NULL, 332, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA DE TUTORIA Y ORIENTACION EDUCATIVA (TOE)', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '1890-01-01', NULL, 297, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ANALISTA DE SISTEMA', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'RACIONALIZACION Y MEJORA CONTINUA', '2016-09-30', NULL, 335, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN MONITOREO', 'ÁREA DE PLANIFICACION Y PRESUPUESTO', 'ESTADISTICA Y MONITOREO', '2016-10-27', NULL, 258, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2015-08-03', NULL, 208, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE TECNICO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '1890-01-01', NULL, 146, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÁREA DE RECURSOS HUMANOS', 'CPPADD', '2017-02-02', NULL, 424, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN INFRAESTRUCTURA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SUPERVISION DE IIEE´S.', '2017-02-10', NULL, 249, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA TÉCNICO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'SOPORTE AL SERVICIO EDUCATIVO (SIAGIE)', '2017-02-09', NULL, 334, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN EDUCACION ESPECIAL', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA ESPECIAL', '2017-02-03', NULL, 174, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2017-03-02', NULL, 202, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN RACIONALIZACION', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'RACIONALIZACION Y MEJORA CONTINUA', '2016-03-01', NULL, 173, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'PATRIMONIO', '2017-03-17', NULL, 303, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OPERADOR DE SERVICIOS Y ATENCION AL CIUDADANO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2017-03-21', NULL, 342, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'CENTRAL TELEFONICA', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2017-05-22', NULL, 321, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADORA', 'ÁREA DE ADMINISTRACIÓN', 'TESORERIA', '2017-06-15', NULL, 187, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2017-06-15', NULL, 368, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '2017-08-07', NULL, 254, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'GESTOR', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'GESTION DE LA EDUCACION BASICA REGULAR', '2017-09-22', NULL, 276, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'ESTADISTICA Y MONITOREO', '2017-09-22', NULL, 152, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'VIDEO REPORTERO', 'ÓRGANO DE DIRECCIÓN', 'COMUNICACIÓN Y PARTICIPACION', '2017-12-22', NULL, 184, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'NOTIFICADOR MOTORIZADO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO - COURIER', '2018-01-03', NULL, 315, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OPERADOR DE PRESTACIONES DE SERVICIOS DE ATENCION AL CIUDADANO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO - COURIER', '2018-01-03', NULL, 213, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROGRAMADOR DE SISTEMA DE INFORMACION', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'TECNOLOGIA DE LA INFORMACION', '2018-02-22', NULL, 445, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÁREA ASESORIA JURIDICA', 'ASUNTOS JUDICIALES', '2018-04-20', NULL, 362, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ASESORÍA JURÍDICA', '', '2018-02-19', NULL, 255, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2018-05-09', NULL, 405, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2018-05-22', NULL, 324, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'JEFE', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', 'JEFATURA', '2018-07-23', NULL, 195, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'DISEÑADORA GRAFICA PUBLICITARIA', 'ÓRGANO DE DIRECCIÓN', 'COMUNICACIÓN Y PARTICIPACION', '2018-05-24', NULL, 360, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SECRETARIA', 'ÓRGANO DE DIRECCIÓN', 'JEFATURA', '2018-08-14', NULL, 272, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2018-08-20', NULL, 380, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2018-09-10', NULL, 322, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2018-10-18', NULL, 449, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÁREA DE ADMINISTRACIÓN', 'PATRIMONIO', '1890-01-01', NULL, 450, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2018-10-18', NULL, 268, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2018-07-26', NULL, 260, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO - PORTA PLIEGOS', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2018-11-28', NULL, 415, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OPERARDOR DE PRESTACION DE SERVICIO DE ATENCION AL CIUDADANO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2018-12-03', NULL, 383, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2019-02-05', NULL, 304, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'NOTIFICADOR', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2019-03-18', NULL, 341, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2019-03-19', NULL, 357, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ANALISTA DE ESTADISTICA Y MONITOREO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'ESTADISTICA Y MONITOREO', '2019-05-30', NULL, 365, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN CLIMA Y CULTURA ORGANIZACIONAL', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2019-06-11', NULL, 236, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA DE GESTION ESCOLAR Y PEDAGOGICO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2019-06-12', NULL, 278, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA LEGAL', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2019-08-05', NULL, 402, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2019-09-05', NULL, 435, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÓRGANO DE DIRECCIÓN', 'JEFATURA', '2019-09-04', NULL, 434, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', 'ESIEP', '2019-09-27', NULL, 441, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES', '2019-11-06', NULL, 462, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2019-10-09', NULL, 454, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2020-02-05', NULL, 475, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2020-02-05', NULL, 474, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TESORERIA', '2020-03-02', NULL, 483, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2020-03-03', NULL, 488, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2020-08-11', NULL, 504, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÁREA DE ADMINISTRACIÓN', 'JEFATURA', '2020-08-12', NULL, 499, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2023-12-05', NULL, 844, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'JEFATURA', '2017-11-10', NULL, 289, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN GESTIÓN ESCOLAR Y PEDAGÓGICO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2020-08-17', NULL, 508, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'JEFATURA', '2020-09-18', NULL, 511, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ANALISTA', 'ÁREA DE ADMINISTRACIÓN', 'CONTABILIDAD', '2020-09-21', NULL, 497, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'PATRIMONIO', '2020-11-12', NULL, 515, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN ASUNTOS JURIDICOS Y LEGALES', 'ÁREA DE ASESORÍA JURÍDICA', 'ASUNTOS JUDICIALES', '2016-06-03', NULL, 309, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE ADMINISTRACIÓN', 'CONTABILIDAD', '2020-12-16', NULL, 503, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2020-11-17', NULL, 516, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2020-03-02', NULL, 486, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2019-01-02', NULL, 401, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2020-12-17', NULL, 501, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ANALISTA DE ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'EQUIPO DE TRAMITE DOCUMENTARIO Y ARCHIVO', '2020-12-18', NULL, 523, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÁREA DE ADMINISTRACIÓN', 'CONTABILIDAD', '2019-12-18', NULL, 467, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA', '2017-10-09', NULL, 417, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'VIGILANCIA', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2015-10-05', NULL, 296, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN GESTIÓN ADMINISTRATIVA', 'ÁREA DE ADMINISTRACIÓN', 'JEFATURA', '2020-12-17', NULL, 522, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2021-01-21', NULL, 547, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2021-01-19', NULL, 549, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÓRGANO DE DIRECCIÓN', 'JEFATURA', '2021-02-09', NULL, 557, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'CHOFER - RESGUARDO', 'ÓRGANO DE DIRECCIÓN', 'JEFATURA', '2021-01-25', NULL, 558, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'RACIONALIZACION Y MEJORA CONTINUA', '2021-05-18', NULL, 126, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO (A)', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA DEL ÁREA DE RECURSOS HUMANOS', '2021-10-26', NULL, 578, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE RECURSOS HUMANOS', 'EQUIPO DE PLANILLAS Y PENSIONES', '2021-11-03', NULL, 599, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÁREA DE RECURSOS HUMANOS', '', '2022-02-04', NULL, 641, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÓRGANO DE DIRECCIÓN', 'CCPADD', '2019-07-08', NULL, 343, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ATENCION AL USUARIO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2022-11-14', NULL, 636, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÓRGANO DE DIRECCIÓN', '', '2022-10-27', NULL, 654, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2023-02-01', NULL, 681, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OFICINISTA', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', '', '2023-01-13', NULL, 674, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA', 'ÁREA DE PLANIFICACION Y PRESUPUESTO', 'PLANEAMIENTO Y PRESUPUESTO', '2023-04-18', NULL, 692, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OPERADOR DE PRESTACIONES DE SERVICIOS DE ATENCION AL CIUDADANO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2023-04-14', NULL, 694, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES', '2023-05-23', NULL, 726, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÁREA DE ASESORIA JURIDICA', '', '2023-11-10', NULL, 827, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', '', '2024-01-01', NULL, 867, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'SECRETARIA', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2024-01-01', NULL, 874, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-01-01', NULL, 863, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', '', '2024-01-01', NULL, 861, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', '', '2024-01-01', NULL, 860, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2024-01-01', NULL, 869, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('APOYO', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2023-04-17', NULL, 695, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CONTRALORIA EXTERNO', '', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2023-11-06', NULL, 823, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2024-01-01', NULL, 877, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2024-01-01', NULL, 878, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ATENCION AL USUARIO II', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2024-08-01', NULL, 327, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2022-04-08', NULL, 688, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2023-06-23', NULL, 758, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2023-11-06', NULL, 822, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('APOYO', 'DOCENTE', 'ÓRGANO DE DIRECCIÓN', 'COMUNICACIÓN Y PARTICIPACION', '2023-11-07', NULL, 834, 4, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2023-12-01', NULL, 838, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2024-02-26', NULL, 882, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÁREA DE ASESORÍA JURÍDICA', '', '2024-02-26', NULL, 884, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SECRETARIA', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2024-03-08', NULL, 888, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2024-03-01', NULL, 892, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', '', '2024-03-20', NULL, 896, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-03-20', NULL, 897, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN SELECCIÓN DE PERSONAL', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2024-04-01', NULL, 901, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR (A) EDUCATIVO PARA EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-04-01', NULL, 906, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA PEDAGÓGICO PARA LA ATENCIÓN EDUCATIVA EN EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-04-01', NULL, 912, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA PEDAGÓGICO PARA LA ATENCIÓN EDUCATIVA EN EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-04-01', NULL, 913, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA PEDAGÓGICO PARA LA ATENCIÓN EDUCATIVA EN EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-04-01', NULL, 914, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PSICÓLOGO(A) DEL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-04-01', NULL, 920, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PSICÓLOGO(A) DEL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-04-01', NULL, 921, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-06-27', NULL, 979, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISSTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES', '2024-04-08', NULL, 924, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR DE GESTION INSTITUCIONAL', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2024-04-08', NULL, 926, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR DE PLANILLAS Y PENSIONES', 'ÁREA DE RECURSOS HUMANOS', '', '2024-04-08', NULL, 927, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES', '2024-04-09', NULL, 929, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ASESORÍA JURÍDICA', '', '2024-04-16', NULL, 930, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÓRGANO DE DIRECCIÓN', '', '2024-04-16', NULL, 937, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('APOYO', 'AUXILIAR ADMINISTRATIVO', 'GESTION DE LA EDUCACION BASICA ALTERNATIVA Y TECNICO PRODUCTIVA', '', '2024-04-16', NULL, 938, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE DE CONTRATACIONES', 'ÁREA DE ADMINISTRACIÓN', '', '2024-04-25', NULL, 940, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-08-04', NULL, 948, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR (A) EDUCATIVO PARA EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-05-15', NULL, 953, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-06-05', NULL, 959, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÓRGANO DE DIRECCIÓN', '', '2024-05-27', NULL, 955, 4, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ANALISTA DE SELECCIÓN', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2024-06-11', NULL, 963, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'TRABAJADOR DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2024-06-28', NULL, 978, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2024-06-19', NULL, 977, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-10-15', NULL, 1038, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE ADMINISTRACIÓN', 'EQUIPO DE LOGÍSTICA', '2024-07-01', NULL, 997, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-10-15', NULL, 1037, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', '', '2024-07-02', NULL, 999, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-08-01', NULL, 1002, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '2024-10-24', NULL, 1036, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'AUXILIAR DE BIBLIOTECA', 'ÁREA DE ADMINISTRACIÓN', 'EQUIPO DE LOGÍSTICA', '2024-07-26', NULL, 1005, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE ADMINISTRACIÓN', 'EQUIPO DE LOGÍSTICA', '2024-08-26', NULL, 1011, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-10-09', NULL, 1033, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-09-12', NULL, 1019, 4, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2024-09-09', NULL, 1018, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS', 'ABOGADO', 'ORGANO DE CONTROL INSTITUCIONAL', 'CONTROL INSTITUCJONAL', '2024-08-01', NULL, 1031, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2024-12-10', NULL, 1080, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2024-09-12', NULL, 1030, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR (A) DEL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-10-21', NULL, 1040, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL I PARA EL EQUIPO ITINERANTE DE CONVIVENCIA ESCOLAR', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-03-13', NULL, 1121, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÁREA DE ASESORÍA JURÍDICA', '', '2024-10-30', NULL, 1048, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL II PARA EQUIPO ITINERANTE DE CONVIVENCIA ESCOLAR', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-03-12', NULL, 1120, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS', 'OPERADOR DE PRESTACIONES DE SERVICIOS DE ATENCION AL CIUDADANO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2024-11-11', NULL, 1052, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS', 'CHOFER', 'ÓRGANO DE DIRECCIÓN', '', '2024-11-19', NULL, 1055, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('APOYO', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-03-10', NULL, 1118, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP -NOMBRADO', 'JEFE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-08-18', NULL, 1226, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-02-25', NULL, 1117, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2025-02-14', NULL, 1116, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-12-03', NULL, 1079, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CONTRALORIA EXTERNO', 'ABOGADO - AUDITOR', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2024-10-18', NULL, 1090, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'AUXILIAR', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-12-10', NULL, 1094, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA EN EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2024-12-01', NULL, 1096, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', '', '2024-12-13', NULL, 1097, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2024-12-12', NULL, 1100, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA LEGAL', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-02-10', NULL, 1114, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ESPECIALISTA ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2025-01-01', NULL, 1103, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ABOGADA', 'ÁREA DE ASESORÍA JURÍDICA', '', '2025-01-01', NULL, 1105, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA', '2025-01-01', NULL, 1106, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2025-01-01', NULL, 1107, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP', 'APOYO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', '', '2025-01-06', NULL, 1113, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ASISTENTA SOCIAL', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2025-01-01', NULL, 1110, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CONTRALORIA EXTERNO', '', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2025-01-15', NULL, 1112, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR (A) EDUCATIVO PARA EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-03-14', NULL, 1125, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-03-03', NULL, 1128, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'ADMINISTRACION DE PERSONAL', '2025-09-04', NULL, 1225, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÓRGANO DE DIRECCIÓN', '', '2025-02-03', NULL, 1131, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA PEDAGÓGICO PARA LA ATENCIÓN EDUCATIVA EN EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-03-19', NULL, 1132, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA DE PREVENCION DE LA VIOLENCIA Y PROMOCION DEL BIENESTAR', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-03-25', NULL, 1137, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE ADMINISTRACIÓN', 'LOGISTICA', '2025-03-24', NULL, 1143, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('APOYO', 'PRACTICANTE', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', '', '2025-08-04', NULL, 1224, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'AUXILIAR DE BIBLIOTECA', 'ÁREA DE RECURSOS HUMANOS', 'EQUIPO DE PLANILLAS Y PENSIONES', '2025-03-31', NULL, 1145, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2025-04-02', NULL, 1146, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DESCAP -DESTACADO CAP', 'ESPECIALISTA DE EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-03-21', NULL, 1147, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'AUXILIAR DE EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-04-24', NULL, 1153, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA - INFRAESTRUCTURA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-08', NULL, 1154, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA - PEDAGOGIA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-04', NULL, 1155, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA - PEDAGOGIA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-03', NULL, 1156, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA LEGAL PAS- UGEL LIMA METROPOLITANA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-04', NULL, 1157, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'AUXILIAR DE EDUCACION', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-07-30', NULL, 1222, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA - INFRAESTRUCTURA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-09', NULL, 1160, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-14', NULL, 1161, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA - ARTICULADOR', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-09', NULL, 1162, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2025-07-30', NULL, 1221, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2025-04-15', NULL, 1166, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'SUPERVISOR UGEL LIMA METROPOLITANA - LEGAL', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-15', NULL, 1167, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'PERSONAL DE SERVICIO', 'ÁREA DE ADMINISTRACIÓN', '', '2025-04-07', NULL, 1168, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAP', 'PLANIFICADOR', 'ÁREA DE PLANIFICACION Y PRESUPUESTO', 'PLANEAMIENTO Y PRESUPUESTO', '2025-04-07', NULL, 1170, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN GESTION ESCOLAR Y PEDAGOGICO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-04-22', NULL, 1173, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', 'EQUIPO DE TRAMITE DOCUMENTARIO Y ARCHIVO', '2025-05-08', NULL, 1174, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'AUXILIAR DE BIBLIOTECA', 'ÁREA DE RECURSOS HUMANOS', 'EQUIPO DE PLANILLAS Y PENSIONES', '2025-05-09', NULL, 1175, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR (A) EDUCATIVO PARA EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-05-21', NULL, 1176, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-05-20', NULL, 1177, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR (A) EDUCATIVO PARA EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-05-21', NULL, 1178, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL DOCENTE ESPECIALISTA EN DISCAPACIDAD VISUAL Y SORDOCEGUERA PARA EL CENTRO DE RECURSOS DE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-05-22', NULL, 1179, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL III PARA EQUIPO ITINERANTE DE CONVIVENCIA ESCOLAR', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-05-22', NULL, 1180, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ASISTENTE ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', '', '2025-05-28', NULL, 1181, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2025-06-10', NULL, 1185, 4, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'PERSONAL DE SERVICIO', 'ÁREA DE RECURSOS HUMANOS', 'EQUIPO ADMINISTRACIÓN DE PERSONAL', '2025-06-26', NULL, 1186, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2025-06-24', NULL, 1187, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2025-06-24', NULL, 1188, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR DE ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2025-06-05', NULL, 1189, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ANALISTA EN PROCESO', 'ÁREA DE PLANIFICACIÓN Y PRESUPUESTO', 'RACIONALIZACION Y MEJORA CONTINUA', '2025-06-09', NULL, 1190, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-06-25', NULL, 1191, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', '', '2025-07-24', NULL, 1218, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2025-07-25', NULL, 1220, 4, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', '', '2025-07-04', NULL, 1196, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA PEDAGÓGICO PARA LA ATENCIÓN EDUCATIVA EN EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-07-10', NULL, 1197, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA PEDAGÓGICO PARA LA ATENCIÓN EDUCATIVA EN EL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-07-10', NULL, 1199, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'AUXILIAR ADMINISTRATIVO', 'ÁREA DE ASESORÍA JURÍDICA', '', '2025-07-14', NULL, 1200, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PRACTICANTE', 'ÓRGANO DE DIRECCIÓN', '', '2025-07-14', NULL, 1201, 3, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE ADMINISTRACIÓN', '', '2025-07-14', NULL, 1204, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ESPECIALISTA EN GESTION ADMINISTRATIVA', 'ÓRGANO DE DIRECCIÓN', '', '2025-07-10', NULL, 1205, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PROFESIONAL', 'ÁREA DE RECURSOS HUMANOS', 'DESARROLLO Y BIENESTAR DEL TALENTO HUMANO', '2025-07-21', NULL, 1206, 3, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PROFESIONAL', 'ÁREA DE RECURSOS HUMANOS', 'JEFATURA', '2025-07-21', NULL, 1207, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PROFESIONAL', 'ÁREA DE RECURSOS HUMANOS', 'SECRETARIA TECNICA - SERVIR', '2025-07-21', NULL, 1208, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PROFESIONAL', 'ÁREA DE ADMINISTRACIÓN', '', '2025-07-21', NULL, 1209, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PROFESIONAL', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS ACTIVOS Y CESANTES', '2025-07-21', NULL, 1210, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'ESCALAFON Y LEGAJOS', '2025-07-21', NULL, 1211, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('PRACTICANTE', 'PROFESIONAL', 'ÓRGANO DE DIRECCIÓN', '', '2025-07-16', NULL, 1212, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'JEFE', 'ÁREA DE ADMINISTRACIÓN', '', '2025-07-16', NULL, 1216, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'ABOGADA', 'ÓRGANO DE DIRECCIÓN', '', '2025-08-04', NULL, 1227, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2025-08-05', NULL, 1229, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2025-08-05', NULL, 1230, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', '', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2025-08-05', NULL, 1231, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', 'PLANILLAS Y PENSIONES - PAGADURIA', '2025-09-01', NULL, 1232, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'ABOGADA', 'ORGANO DE CONTROL INSTITUCIONAL', '', '2025-09-01', NULL, 1233, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'INGENIERO', 'ÁREA DE SUPERVISIÓN Y GESTIÓN DEL SERVICIO EDUCATIVO', '', '2025-09-01', NULL, 1234, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAPC -CONTRATADO', 'OFICINISTA', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2025-09-01', NULL, 1235, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'OPERADOR DE PRESTACIONES DE SERVICIOS DE ATENCION AL CIUDADANO', 'ÁREA DE ADMINISTRACIÓN', 'ACTAS CERTIFICADOS Y TITULOS', '2025-09-02', NULL, 1236, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PSICÓLOGO(A) DEL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-09-02', NULL, 1237, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PSICÓLOGO(A) DEL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-09-02', NULL, 1238, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PSICÓLOGO(A) DEL SERVICIO EDUCATIVO HOSPITALARIO', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-09-02', NULL, 1239, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2025-08-20', NULL, 1240, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'ARCHIVO', '2025-08-21', NULL, 1241, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE RECURSOS HUMANOS', '', '2025-09-18', NULL, 1242, 2, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO EN ARCHIVO', 'ÁREA DE ADMINISTRACIÓN', 'TRAMITE DOCUMENTARIO', '2025-09-08', NULL, 1243, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'TECNICO ADMINISTRATIVO', 'ÁREA DE RECURSOS HUMANOS', '', '2025-09-29', NULL, 1244, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'COORDINADOR', 'ÁREA DE RECURSOS HUMANOS', 'RECLUTAMIENTO Y SELECCIÓN DE PERSONAL', '2025-09-22', NULL, 1245, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('CAS -CONT.ADM.SERV.', 'PROFESIONAL DE APOYO SAEI', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', '', '2025-09-23', NULL, 1246, 1, 1, CURRENT_TIMESTAMP);
INSERT INTO jobassignments (modalidad, cargo, area, equipo, fechaini, fechafin, user_id, workschedule_id, estado, created_at) 
VALUES ('DISP III', 'DOCENTE', 'ÁREA DE GESTIÓN DE LA EDUCACIÓN BASICA REGULAR Y ESPECIAL', 'EBR', '2025-09-08', NULL, 1247, 2, 1, CURRENT_TIMESTAMP);

-- Total de registros procesados: 383
-- Mapeo de horarios:
-- id_tipo_usuario 1,9 -> workschedule_id 1 (Horario 8:00-16:45)
-- id_tipo_usuario 2,6 -> workschedule_id 2 (Horario 8:00-13:00)
-- id_tipo_usuario 3   -> workschedule_id 3 (Horario 13:00-18:00)
-- id_tipo_usuario 7   -> workschedule_id 4 (Horario 8:15-17:15)

-- Permiso de lactancia para JENIFFER JULISSA 
INSERT INTO permissions (abrevia, descripcion, fechaini, fechafin, estado, jobassignment_id, user_id, permissiontype_id, usercrea) VALUES
('LACT', 'Licencia por lactancia - 1 hora diaria', '2025-01-15', '2025-12-31', 1, 281, 1030, 2, 1)
ON CONFLICT DO NOTHING;

-- Programación de lactancia para JENIFFER JULISSA - Ejemplo de cambio de modo por períodos
INSERT INTO lactation_schedules (permission_id, fecha_desde, fecha_hasta, modo, minutos_diarios, observaciones, usercrea) VALUES
-- Primer mes: modo INICIO (llega 1 hora después)
(1, '2025-01-15', '2025-12-31', 'INICIO', 60, 'todo los meses - entrada 1 hora después (9:00 AM)', 1)

-- licencia sin goce
-- Permiso LSG para Carlos (para permitir segundo cargo)
INSERT INTO permissions (abrevia, descripcion, fechaini, fechafin, estado, jobassignment_id, user_id, permissiontype_id, usercrea) VALUES
('LSG', 'Licencia sin goce para segundo empleo', '2025-07-01', '2025-12-31', 1, 157, 255, 1, 1)
ON CONFLICT DO NOTHING;

-- Segundo cargo para Carlos (permitido por LSG)
INSERT INTO jobassignments (modalidad, cargo, area, equipo, jefe, fechaini, fechafin, user_id, workschedule_id, salario, usercrea) VALUES
('CONSULTOR', 'Consultor Externo', 'Proyectos', 'Consultoría', 'Director Externo', '2025-07-01', '2025-12-10', 255, 1, 2000.00, 1)
ON CONFLICT DO NOTHING;