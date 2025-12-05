#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script para procesar asistencia y generar registros en dailyattendances
Base de datos: asistenciaV2r
"""

import sys
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime, timedelta, time
import argparse

# Configuración de conexión
DB_CONFIG = {
    'dbname': 'asistenciaV2r',
    'user': 'nestor',
    'password': 'Arequipa@2018',
    'host': 'localhost',
    'port': 5432
}


def conectar_bd():
    """Establece conexión con la base de datos"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        print(f"Error al conectar a la base de datos: {e}")
        sys.exit(1)


def obtener_calendario(conn, fecha):
    """Verifica si existe calendario para la fecha"""
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("""
        SELECT id, fecha, estado, descripcion
        FROM calendardays
        WHERE fecha = %s
    """, (fecha,))
    return cursor.fetchone()


def obtener_usuarios_activos(conn, fecha, dni=None):
    """Obtiene usuarios con asignaciones activas en la fecha"""
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    sql = """
        SELECT DISTINCT 
            u.id as user_id,
            u.dni,
            u.nombre,
            u.apellidos,
            ja.id as jobassignment_id,
            ja.fechaini,
            ja.fechafin,
            ws.id as workschedule_id,
            ws.horaini,
            ws.horafin,
            ws.tolerancia_min
        FROM users u
        INNER JOIN jobassignments ja ON ja.user_id = u.id
        INNER JOIN workschedules ws ON ws.id = ja.workschedule_id
        WHERE ja.estado = 1
        AND ja.fechaini <= %s
        AND (ja.fechafin IS NULL OR ja.fechafin >= %s)
    """
    
    params = [fecha, fecha]
    
    if dni:
        sql += " AND u.dni = %s"
        params.append(dni)
    
    sql += " ORDER BY u.dni"
    
    cursor.execute(sql, params)
    return cursor.fetchall()


def obtener_marcaciones(conn, user_id, fecha):
    """Obtiene todas las marcaciones de un usuario en una fecha"""
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("""
        SELECT 
            id,
            fechahora,
            hora,
            tipo_marcaje
        FROM attendances
        WHERE user_id = %s
        AND fecha = %s
        AND estado = 1
        ORDER BY hora
    """, (user_id, fecha))
    return cursor.fetchall()


def obtener_permisos_activos(conn, user_id, fecha, jobassignment_id, cargo_fechaini, cargo_fechafin):
    """
    Obtiene todos los permisos activos del usuario en la fecha especificada para un cargo específico
    
    Validaciones:
    1. El permiso debe estar vigente en la fecha (fecha BETWEEN fechaini AND fechafin)
    2. Si el cargo tiene fechafin, el permiso debe tener fechafin <= cargo.fechafin
    3. LSG se filtra por jobassignment_id específico
    4. Otros permisos aplican a todos los cargos del usuario
    """
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    # Obtener permisos generales (vacaciones, LSG, maternidad, enfermedad, etc.)
    # IMPORTANTE: LSG se filtra por jobassignment_id, otros permisos aplican a todos los cargos
    cursor.execute("""
        SELECT 
            p.id as permission_id,
            p.abrevia,
            p.descripcion,
            p.fechaini,
            p.fechafin,
            p.jobassignment_id,
            pt.id as permissiontype_id,
            pt.codigo as tipo_codigo,
            pt.descripcion as tipo_descripcion
        FROM permissions p
        INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
        WHERE p.user_id = %s
        AND p.estado = 1
        AND %s BETWEEN p.fechaini AND p.fechafin
        AND pt.codigo != 'LACTANCIA'
        AND (
            -- LSG solo aplica al cargo específico asociado al permiso
            (pt.codigo = 'LSG' AND p.jobassignment_id = %s)
            OR
            -- Otros permisos (VACACIONES, ENFERMEDAD, MATERNIDAD, etc.) aplican a todos los cargos
            (pt.codigo != 'LSG')
        )
        AND (
            -- Validar que el permiso esté dentro del rango del cargo
            p.fechaini >= %s
            AND (
                -- Si el cargo tiene fechafin, el permiso debe terminar antes o en la misma fecha
                (%s IS NULL) OR (p.fechafin <= %s)
            )
        )
        ORDER BY pt.id
    """, (user_id, fecha, jobassignment_id, cargo_fechaini, cargo_fechafin, cargo_fechafin))
    permisos_generales = cursor.fetchall()
    
    # Obtener permiso de lactancia con su programación
    cursor.execute("""
        SELECT 
            p.id as permission_id,
            p.abrevia,
            pt.id as permissiontype_id,
            pt.codigo as tipo_codigo,
            ls.modo,
            ls.minutos_diarios
        FROM permissions p
        INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
        INNER JOIN lactation_schedules ls ON ls.permission_id = p.id
        WHERE p.user_id = %s
        AND p.estado = 1
        AND pt.codigo = 'LACTANCIA'
        AND %s BETWEEN p.fechaini AND p.fechafin
        AND %s BETWEEN ls.fecha_desde AND ls.fecha_hasta
        AND ls.estado = 1
        AND (
            -- Validar que el permiso esté dentro del rango del cargo
            p.fechaini >= %s
            AND (
                -- Si el cargo tiene fechafin, el permiso debe terminar antes o en la misma fecha
                (%s IS NULL) OR (p.fechafin <= %s)
            )
        )
        LIMIT 1
    """, (user_id, fecha, fecha, cargo_fechaini, cargo_fechafin, cargo_fechafin))
    lactancia = cursor.fetchone()
    
    return {
        'permisos_generales': permisos_generales,
        'lactancia': lactancia
    }


def calcular_horario_esperado(horario, lactancia):
    """Calcula horario esperado considerando lactancia"""
    horaini_esperada = horario['horaini']
    horafin_esperada = horario['horafin']
    if lactancia:
        minutos = int(lactancia.get('minutos_diarios') or 0)
        if lactancia.get('modo') == 'INICIO' and minutos > 0:
            dt = datetime.combine(datetime.today(), horaini_esperada) + timedelta(minutes=minutos)
            horaini_esperada = dt.time()
        elif lactancia.get('modo') == 'FIN' and minutos > 0:
            dt = datetime.combine(datetime.today(), horafin_esperada) - timedelta(minutes=minutos)
            horafin_esperada = dt.time()
    return horaini_esperada, horafin_esperada


def calcular_asistencia(horario, marcaciones, permisos, estado_calendario):
    """Calcula los campos de asistencia según las reglas de negocio"""
    
    lactancia = permisos.get('lactancia')
    permisos_generales = permisos.get('permisos_generales', [])
    
    resultado = {
        'horaini': None,
        'horafin': None,
        'nummarca': len(marcaciones),
        'horaint': ','.join([str(m['hora']) for m in marcaciones]),
        'mintarde': 0,
        'retarde': 0,
        'horaslab': 0,
        'minlab': 0,
        'horas_extras': 0,
        'obs': '',
        'final': '',
        'minutos_lactancia': lactancia['minutos_diarios'] if lactancia else 0,
        'modo_lactancia': lactancia['modo'] if lactancia else None,
        'flaglab': 1 if estado_calendario == 1 else 0
    }
    
    # REGLA 1: VACACIONES (permissiontype_id=3)
    # Afecta a TODOS los días (estado 0, 1, 2, 3) - poner "V" en obs y final
    permiso_vacaciones = next((p for p in permisos_generales if p['tipo_codigo'] == 'VACACIONES'), None)
    if permiso_vacaciones:
        resultado['obs'] = 'V'
        resultado['final'] = 'V'
        return resultado
    
    # REGLA 4: LSG (permissiontype_id=1)
    # Funciona igual que otros permisos (punto 3), pero permite nuevo cargo
    # Solo afecta días laborables (estado=1)
    permiso_lsg = next((p for p in permisos_generales if p['tipo_codigo'] == 'LSG'), None)
    if permiso_lsg and estado_calendario == 1:
        abrevia = permiso_lsg.get('abrevia', 'LSG')
        resultado['obs'] = abrevia
        resultado['final'] = abrevia
        return resultado
    
    # REGLA 3: OTROS PERMISOS (maternidad, enfermedad, licencia con goce, etc.)
    # permissiontype_id=4,5,6,... - Solo afecta días laborables (estado=1)
    # Se pone la abreviatura en obs y final
    otros_permisos = [p for p in permisos_generales 
                      if p['tipo_codigo'] not in ['VACACIONES', 'LSG', 'LACTANCIA']]
    if otros_permisos and estado_calendario == 1:
        # Tomar el primer permiso encontrado (ordenado por id)
        permiso = otros_permisos[0]
        abrevia = permiso.get('abrevia', permiso['tipo_codigo'][:3])
        resultado['obs'] = abrevia
        resultado['final'] = abrevia
        return resultado
    
    # REGLA 2: LACTANCIA
    # No afecta los días, solo modifica el horario (ya implementado)
    # Continuar con el procesamiento normal de asistencia
    
    # Si no hay marcaciones
    if not marcaciones:
        if estado_calendario == 1:  # Día laborable
            resultado['obs'] = 'F'
            resultado['final'] = 'F'
        return resultado
    
    # Calcular horario esperado con lactancia
    horaini_esperada, horafin_esperada = calcular_horario_esperado(horario, lactancia)
    
    ingresos = [m['hora'] for m in marcaciones if m.get('tipo_marcaje') == 'INGRESO']
    salidas = [m['hora'] for m in marcaciones if m.get('tipo_marcaje') == 'SALIDA']
    primera_marca = marcaciones[0]['hora']
    ultima_marca = marcaciones[-1]['hora'] if len(marcaciones) > 1 else None
    ingreso_marca = min(ingresos) if ingresos else None
    salida_marca = max(salidas) if salidas else None
    
    # Solo procesar si es día laborable (estado=1)
    if estado_calendario != 1:
        # Días no laborables: solo contar marcaciones
        resultado['horaint'] = ','.join([str(m['hora']) for m in marcaciones])
        return resultado
    
    # Día laborable (estado=1)
    tolerancia = horario['tolerancia_min']
    
    # Verificar ingreso (sin aplicar tolerancia en la condición)
    if ingreso_marca:
        resultado['horaini'] = ingreso_marca
        if ingreso_marca > horaini_esperada:
            dt_esperada = datetime.combine(datetime.today(), horaini_esperada)
            dt_real = datetime.combine(datetime.today(), ingreso_marca)
            minutos_tarde = (dt_real - dt_esperada).seconds // 60
            if minutos_tarde < tolerancia:
                resultado['mintarde'] = minutos_tarde
            else:
                resultado['retarde'] = minutos_tarde
    else:
        dt_esperada = datetime.combine(datetime.today(), horaini_esperada)
        if primera_marca:
            dt_real = datetime.combine(datetime.today(), primera_marca)
            minutos_tarde = int((dt_real - dt_esperada).total_seconds() // 60)
            if minutos_tarde > 0:
                resultado['retarde'] = minutos_tarde
    
    # Verificar salida
    if salida_marca and salida_marca >= horafin_esperada:
        resultado['horafin'] = salida_marca
        dt_esperada = datetime.combine(datetime.today(), horafin_esperada)
        dt_real = datetime.combine(datetime.today(), salida_marca)
        minutos_extras = (dt_real - dt_esperada).seconds // 60
        if minutos_extras > 0 and resultado['horaini'] is not None:
            resultado['horas_extras'] = minutos_extras
    
    # Calcular horas laboradas
    if ingreso_marca and salida_marca:
        dt_inicio = datetime.combine(datetime.today(), ingreso_marca)
        dt_fin = datetime.combine(datetime.today(), salida_marca)
        resultado['minlab'] = (dt_fin - dt_inicio).seconds // 60
        resultado['horaslab'] = round(resultado['minlab'] / 60, 2)
    
    # Determinar obs y final
    tiene_ingreso = resultado['horaini'] is not None
    tiene_salida = resultado['horafin'] is not None

    if tiene_ingreso and tiene_salida and resultado['mintarde'] == 0 and resultado['retarde'] == 0:
        resultado['obs'] = 'A'
        resultado['final'] = 'A'
    elif not tiene_ingreso and not tiene_salida:
        resultado['obs'] = 'F'
        resultado['final'] = 'F'
    elif not tiene_ingreso:
        if resultado['mintarde'] > 0:
            resultado['obs'] = str(resultado['mintarde'])
            resultado['final'] = str(resultado['mintarde'])
        else:
            resultado['obs'] = 'FI'
            resultado['final'] = 'FI'
        if not tiene_salida:
            resultado['obs'] += ' - FS'
            resultado['final'] += ' - FS'
    elif not tiene_salida:
        if resultado['mintarde'] > 0 or resultado['retarde'] > 0:
            valor = resultado['mintarde'] if resultado['mintarde'] > 0 else resultado['retarde']
            resultado['obs'] = f"{valor} - FS"
            resultado['final'] = f"{valor} - FS"
        else:
            resultado['obs'] = 'FS'
            resultado['final'] = 'FS'
    elif resultado['mintarde'] > 0 or resultado['retarde'] > 0:
        valor = resultado['mintarde'] if resultado['mintarde'] > 0 else resultado['retarde']
        resultado['obs'] = str(valor)
        resultado['final'] = str(valor)
    
    return resultado



def ya_procesado(conn, jobassignment_id, fecha):
    """Verifica si ya existe registro procesado"""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id FROM dailyattendances
        WHERE jobassignment_id = %s AND fecha = %s
    """, (jobassignment_id, fecha))
    return cursor.fetchone() is not None


def insertar_asistencia(conn, jobassignment_id, fecha, datos):
    """Inserta o actualiza registro en dailyattendances"""
    cursor = conn.cursor()
    
    sql = """
        INSERT INTO dailyattendances (
            jobassignment_id, fecha, anio, mes,
            horaini, horafin, nummarca, obs, mintarde, retarde,
            minutos_lactancia, modo_lactancia, final, horaint,
            flaglab, horaslab, minlab, horas_extras, estado,
            created_at
        ) VALUES (
            %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s,
            %s, %s, %s, %s, 1,
            CURRENT_TIMESTAMP
        )
        ON CONFLICT (jobassignment_id, fecha) DO UPDATE SET
            horaini = EXCLUDED.horaini,
            horafin = EXCLUDED.horafin,
            nummarca = EXCLUDED.nummarca,
            obs = EXCLUDED.obs,
            mintarde = EXCLUDED.mintarde,
            retarde = EXCLUDED.retarde,
            minutos_lactancia = EXCLUDED.minutos_lactancia,
            modo_lactancia = EXCLUDED.modo_lactancia,
            final = EXCLUDED.final,
            horaint = EXCLUDED.horaint,
            flaglab = EXCLUDED.flaglab,
            horaslab = EXCLUDED.horaslab,
            minlab = EXCLUDED.minlab,
            horas_extras = EXCLUDED.horas_extras,
            updated_at = CURRENT_TIMESTAMP
    """
    
    cursor.execute(sql, (
        jobassignment_id, fecha, fecha.year, fecha.month,
        datos['horaini'], datos['horafin'], datos['nummarca'], 
        datos['obs'], datos['mintarde'], datos['retarde'],
        datos['minutos_lactancia'], datos['modo_lactancia'], 
        datos['final'], datos['horaint'],
        datos['flaglab'], datos['horaslab'], datos['minlab'], 
        datos['horas_extras']
    ))


def procesar_fecha(conn, fecha, dni=None):
    """Procesa asistencia para una fecha específica"""
    
    # 1. Verificar calendario
    calendario = obtener_calendario(conn, fecha)
    if not calendario:
        print(f"⚠️  No hay calendario programado para {fecha}")
        return 0
    
    print(f"\n📅 Procesando fecha: {fecha} ({calendario['descripcion']})")
    print(f"   Estado del día: {calendario['estado']} (0=feriado, 1=laborable, 2=recuperable)")
    
    # 2. Obtener usuarios activos
    usuarios = obtener_usuarios_activos(conn, fecha, dni)
    if not usuarios:
        print(f"   No hay usuarios activos para procesar")
        return 0
    
    print(f"   Usuarios a procesar: {len(usuarios)}")
    
    procesados = 0
    
    for usuario in usuarios:
        # 3. Obtener marcaciones
        marcaciones = obtener_marcaciones(conn, usuario['user_id'], fecha)
        
        # 4. Obtener todos los permisos activos (lactancia, vacaciones, LSG, etc.)
        # IMPORTANTE: LSG se filtra por jobassignment_id específico
        # VALIDACIÓN: Los permisos deben estar dentro del rango de fechas del cargo
        permisos = obtener_permisos_activos(
            conn, 
            usuario['user_id'], 
            fecha, 
            usuario['jobassignment_id'],
            usuario['fechaini'],
            usuario['fechafin']
        )
        
        # 5. Calcular asistencia
        datos_asistencia = calcular_asistencia(
            usuario, 
            marcaciones, 
            permisos,
            calendario['estado']
        )
        
        # 6. Insertar en dailyattendances
        try:
            insertar_asistencia(
                conn, 
                usuario['jobassignment_id'], 
                fecha, 
                datos_asistencia
            )
            procesados += 1
            
            # Mostrar resumen
            marca_info = f"{datos_asistencia['nummarca']} marcas"
            if datos_asistencia['horaini']:
                marca_info += f" | In: {datos_asistencia['horaini']}"
            if datos_asistencia['horafin']:
                marca_info += f" | Sal: {datos_asistencia['horafin']}"
            if datos_asistencia['obs']:
                marca_info += f" | {datos_asistencia['obs']}"
            
            print(f"   ✓ {usuario['dni']} - {usuario['nombre']}: {marca_info}")
            
        except Exception as e:
            print(f"   ✗ Error procesando {usuario['dni']}: {e}")
            conn.rollback()
            continue
    
    conn.commit()
    return procesados


def main():
    parser = argparse.ArgumentParser(
        description='Procesar asistencia de personal'
    )
    parser.add_argument(
        '--fecha-inicio',
        type=str,
        help='Fecha de inicio (YYYY-MM-DD)'
    )
    parser.add_argument(
        '--fecha-fin',
        type=str,
        help='Fecha de fin (YYYY-MM-DD)'
    )
    parser.add_argument(
        '--dni',
        type=str,
        help='DNI específico a procesar'
    )
    
    args = parser.parse_args()
    
    # Determinar rango de fechas
    if not args.fecha_inicio and not args.fecha_fin:
        # Por defecto: ayer
        fecha_inicio = datetime.now().date() - timedelta(days=1)
        fecha_fin = fecha_inicio
        print("📌 Sin parámetros: procesando fecha de ayer")
    else:
        fecha_inicio = datetime.strptime(args.fecha_inicio, '%Y-%m-%d').date() if args.fecha_inicio else datetime.now().date() - timedelta(days=1)
        fecha_fin = datetime.strptime(args.fecha_fin, '%Y-%m-%d').date() if args.fecha_fin else fecha_inicio
    
    print(f"\n{'='*60}")
    print(f"  PROCESAMIENTO DE ASISTENCIA")
    print(f"{'='*60}")
    print(f"Período: {fecha_inicio} al {fecha_fin}")
    if args.dni:
        print(f"DNI: {args.dni}")
    print(f"{'='*60}")
    
    # Conectar a BD
    conn = conectar_bd()
    
    try:
        total_procesados = 0
        fecha_actual = fecha_inicio
        
        while fecha_actual <= fecha_fin:
            procesados = procesar_fecha(conn, fecha_actual, args.dni)
            total_procesados += procesados
            fecha_actual += timedelta(days=1)
        
        print(f"\n{'='*60}")
        print(f"✅ Proceso completado")
        print(f"   Total registros procesados: {total_procesados}")
        print(f"{'='*60}\n")
        
    except Exception as e:
        print(f"\n❌ Error durante el procesamiento: {e}")
        conn.rollback()
    finally:
        conn.close()


if __name__ == '__main__':
    main()
