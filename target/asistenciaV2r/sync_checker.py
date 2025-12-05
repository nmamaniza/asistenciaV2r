# -*- coding: utf-8 -*-
"""
SYNC_ALL_REALTIME.PY
====================
Sincronizador que procesa TODAS las marcaciones y muestra resultados en tiempo real
- Obtiene TODAS las marcaciones de los relojes (sin filtro de duplicados)
- Muestra cada marcación procesada en consola inmediatamente
- Incluye estadísticas en tiempo real y resumen final
"""

import sys
sys.path.append("zk")
from datetime import datetime, timedelta
import psycopg2
from zk import ZK, const
import datetime as dt
import pytz as tz
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
import queue
from contextlib import contextmanager
from collections import defaultdict
import time

# Configuración de logging con codificación UTF-8
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('sync_all_realtime.log', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)

if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')
logger = logging.getLogger(__name__)


class RealtimeAttendanceSync:
    def __init__(self, db_config):
        self.db_config = db_config
        self.timezone = tz.timezone('America/Lima')
        self.display_lock = threading.Lock()
        self.connection_pool = queue.Queue(maxsize=10)
        
        # Contadores en tiempo real
        self.stats = {
            'total_fetched': 0,
            'total_processed': 0,
            'total_inserted': 0,
            'total_duplicates': 0,
            'total_errors': 0,
            'by_clock': defaultdict(lambda: {'fetched': 0, 'processed': 0, 'inserted': 0, 'duplicates': 0, 'last_attendance': None}),
            'by_type': defaultdict(int)
        }
        self.stats_lock = threading.Lock()
        
        # Configuración de conexión
        self.connection_config = {
            'timeout': 10,
            'max_retries': 3,
            'retry_delay': 2,
            'max_workers': 4
        }
        
        self._init_connection_pool()
    
    def _init_connection_pool(self):
        """Inicializa el pool de conexiones a la base de datos"""
        try:
            for _ in range(5):
                conn = psycopg2.connect(**self.db_config)
                self.connection_pool.put(conn)
            logger.info("🔗 Pool de conexiones a BD inicializado")
        except Exception as e:
            logger.error(f"❌ Error inicializando pool de conexiones: {e}")
    
    @contextmanager
    def get_db_connection(self):
        """Obtiene una conexión de la base de datos del pool"""
        conn = None
        try:
            try:
                conn = self.connection_pool.get(timeout=5)
            except queue.Empty:
                conn = psycopg2.connect(**self.db_config)
            
            if conn.closed:
                conn = psycopg2.connect(**self.db_config)
            
            yield conn
            
        except Exception as e:
            logger.error(f"Error en conexión a BD: {e}")
            if conn:
                conn.rollback()
            raise
        finally:
            if conn and not conn.closed:
                try:
                    self.connection_pool.put_nowait(conn)
                except queue.Full:
                    conn.close()
    
    def update_stats(self, clock_id=None, stat_type=None, increment=1):
        """Actualiza estadísticas en tiempo real de forma thread-safe"""
        with self.stats_lock:
            if clock_id and stat_type:
                self.stats['by_clock'][clock_id][stat_type] += increment
                    
            if stat_type == 'fetched':
                self.stats['total_fetched'] += increment
            elif stat_type == 'processed':
                self.stats['total_processed'] += increment
            elif stat_type == 'inserted':
                self.stats['total_inserted'] += increment
            elif stat_type == 'duplicates':
                self.stats['total_duplicates'] += increment
            elif stat_type == 'error':
                self.stats['total_errors'] += increment
    
    def update_last_attendance(self, clock_id, attendance_data):
        """Actualiza la última marcación del reloj (insertada o duplicada)"""
        with self.stats_lock:
            current_last = self.stats['by_clock'][clock_id]['last_attendance']
            
            # Si no hay última marcación, actualizar directamente
            if current_last is None:
                self.stats['by_clock'][clock_id]['last_attendance'] = attendance_data
                return
            
            # Comparar timestamps para mantener la más reciente
            current_timestamp = current_last.get('timestamp')
            new_timestamp = attendance_data.get('timestamp')
            
            if new_timestamp and current_timestamp:
                if new_timestamp > current_timestamp:
                    self.stats['by_clock'][clock_id]['last_attendance'] = attendance_data
            else:
                # Si no hay timestamps, comparar por fechahora string
                if attendance_data['fechahora'] > current_last['fechahora']:
                    self.stats['by_clock'][clock_id]['last_attendance'] = attendance_data
    
    def display_realtime_stats(self):
        """Muestra estadísticas en tiempo real"""
        with self.stats_lock:
            print(f"\r📊 Progreso: Obtenidas={self.stats['total_fetched']} | "
                  f"Procesadas={self.stats['total_processed']} | "
                  f"Insertadas={self.stats['total_inserted']} | "
                  f"Duplicadas={self.stats['total_duplicates']} | "
                  f"Errores={self.stats['total_errors']}", end='', flush=True)
    
    def get_all_clock_attendances(self, zk_config, reloj_id):
        """Obtiene TODAS las marcaciones del reloj sin filtros"""
        max_retries = self.connection_config['max_retries']
        retry_delay = self.connection_config['retry_delay']
        timeout = self.connection_config['timeout']
        
        for attempt in range(max_retries):
            try:
                logger.info(f"🔄 Intento {attempt + 1}/{max_retries} - Conectando a {reloj_id} ({zk_config['ip']})")
                
                zk = ZK(
                    zk_config['ip'], 
                    port=zk_config.get('port', 4370), 
                    timeout=timeout, 
                    password=0, 
                    force_udp=False, 
                    ommit_ping=False
                )
                
                if zk.connect():
                    logger.info(f"✅ Conectado exitosamente a {reloj_id}")
                    
                    try:
                        attendances = zk.get_attendance()
                        count = len(attendances) if attendances else 0
                        
                        self.update_stats(reloj_id, 'fetched', count)
                        
                        with self.display_lock:
                            print(f"\n📥 {reloj_id}: {count} marcaciones obtenidas del dispositivo")
                        
                        return attendances if attendances else []
                        
                    except Exception as e:
                        logger.error(f"❌ Error obteniendo marcaciones de {reloj_id}: {e}")
                        return []
                    finally:
                        try:
                            zk.disconnect()
                        except:
                            pass
                else:
                    logger.warning(f"⚠️ No se pudo establecer conexión a {reloj_id} en intento {attempt + 1}")
                    
            except Exception as e:
                logger.error(f"❌ Error en intento {attempt + 1} para {reloj_id}: {e}")
                
                if attempt < max_retries - 1:
                    logger.info(f"⏳ Esperando {retry_delay} segundos antes del siguiente intento...")
                    time.sleep(retry_delay)
        
        logger.error(f"💥 Falló conexión a {reloj_id} después de {max_retries} intentos")
        return []
    
    def check_attendance_exists(self, dni, fechahora, reloj):
        """Verifica si una marcación ya existe en la BD (dni, fechahora, reloj)"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT COUNT(*) 
                    FROM attendances 
                    WHERE dni = %s AND fechahora = %s AND reloj = %s
                    """
                    cur.execute(sql, (dni, fechahora, reloj))
                    result = cur.fetchone()
                    return result[0] > 0 if result else False
        except Exception as e:
            logger.error(f"Error verificando duplicado: {e}")
            return False
    
    def get_user_info(self, dni):
        """Obtiene información del usuario por DNI"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT u.id, u.dni, u.nombre, u.apellidos, u.estado
                    FROM users u
                    WHERE u.dni = %s AND u.estado = 1
                    """
                    cur.execute(sql, (str(dni),))
                    result = cur.fetchone()
                    
                    if result:
                        return {
                            'user_id': result[0],
                            'dni': result[1],
                            'nombre': result[2],
                            'apellidos': result[3],
                            'estado': result[4]
                        }
                    return None
        except Exception as e:
            logger.error(f"Error obteniendo información del usuario {dni}: {e}")
            return None
    
    def get_validated_job_assignments(self, user_id, fecha_marcacion):
        """Obtiene job assignments activos con validación estricta de fechas"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT ja.id, ja.modalidad, ja.cargo, ja.area, ja.fechaini, ja.fechafin,
                           ws.id as workschedule_id, ws.descripcion, ws.horaini, ws.horafin, 
                           ws.tolerancia_min, ws.horas_jornada
                    FROM jobassignments ja
                    INNER JOIN workschedules ws ON ja.workschedule_id = ws.id
                    WHERE ja.user_id = %s 
                    AND ja.estado = 1
                    AND ws.estado = 1
                    AND ja.fechaini <= %s
                    AND (ja.fechafin IS NULL OR ja.fechafin >= %s)
                    ORDER BY ja.fechaini DESC
                    """
                    cur.execute(sql, (user_id, fecha_marcacion, fecha_marcacion))
                    results = cur.fetchall()
                    
                    job_assignments = []
                    for result in results:
                        job_assignments.append({
                            'jobassignment_id': result[0],
                            'modalidad': result[1],
                            'cargo': result[2],
                            'area': result[3],
                            'fechaini': result[4],
                            'fechafin': result[5],
                            'workschedule_id': result[6],
                            'horario_descripcion': result[7],
                            'horaini': result[8],
                            'horafin': result[9],
                            'tolerancia_min': result[10] or 15,
                            'horas_jornada': result[11]
                        })
                    
                    return job_assignments
                    
        except Exception as e:
            logger.error(f"Error obteniendo job assignments: {e}")
            return []
    
    def get_calendar_day_info(self, fecha_marcacion):
        """Obtiene información del día según calendardays"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT estado, descripcion 
                    FROM calendardays 
                    WHERE fecha = %s
                    """
                    cur.execute(sql, (fecha_marcacion,))
                    result = cur.fetchone()
                    
                    if result:
                        estado, descripcion = result
                        is_working = (estado == 1)
                        mensaje = "Día laborable" if estado == 1 else "Día no laborable"
                        
                        return {
                            'is_working': is_working,
                            'estado': estado,
                            'descripcion': descripcion or mensaje,
                            'mensaje': mensaje
                        }
                    else:
                        return {
                            'is_working': False,
                            'estado': 0,
                            'descripcion': 'Fecha no encontrada en calendario',
                            'mensaje': 'Día no laborable'
                        }
                        
        except Exception as e:
            logger.error(f"Error obteniendo información del día: {e}")
            return {
                'is_working': False,
                'estado': 0,
                'descripcion': 'Error al consultar calendario',
                'mensaje': 'Día no laborable'
            }
    
    def get_lactancia_adjustment(self, user_id, fecha_marcacion):
        """Obtiene el ajuste de lactancia para un usuario"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT p.id as permission_id, ls.modo, ls.minutos_diarios, 
                           ls.fecha_desde, ls.fecha_hasta
                    FROM permissions p
                    INNER JOIN permissiontypes pt ON p.permissiontype_id = pt.id
                    INNER JOIN lactation_schedules ls ON p.id = ls.permission_id
                    WHERE p.user_id = %s 
                    AND p.estado = 1
                    AND pt.id = 2
                    AND p.fechaini <= %s
                    AND p.fechafin >= %s
                    AND ls.fecha_desde <= %s
                    AND ls.fecha_hasta >= %s
                    AND ls.estado = 1
                    ORDER BY ls.fecha_desde DESC
                    LIMIT 1
                    """
                    cur.execute(sql, (user_id, fecha_marcacion, fecha_marcacion, 
                                    fecha_marcacion, fecha_marcacion))
                    result = cur.fetchone()
                    
                    if result:
                        return {
                            'minutos': result[2] or 60,
                            'modo': result[1] or 'INICIO',
                            'permission_id': result[0],
                            'fecha_desde': result[3],
                            'fecha_hasta': result[4]
                        }
            
            return {'minutos': 0, 'modo': None, 'permission_id': None}
            
        except Exception as e:
            logger.error(f"Error obteniendo ajuste de lactancia: {e}")
            return {'minutos': 0, 'modo': None, 'permission_id': None}
    
    def classify_attendance_type(self, hora_marcacion, job_assignments, user_id, fecha_marcacion):
        """Clasifica el tipo de marcación según workschedules"""
        if not job_assignments:
            return "INTERMEDIO"
        
        job_assignment = job_assignments[0]
        horaini = job_assignment['horaini']
        horafin = job_assignment['horafin']
        tolerancia_min = job_assignment['tolerancia_min']
        
        if isinstance(hora_marcacion, str):
            hora_marcacion = datetime.strptime(hora_marcacion, '%H:%M:%S').time()
        elif isinstance(hora_marcacion, datetime):
            hora_marcacion = hora_marcacion.time()
        
        if isinstance(horaini, timedelta):
            horaini = (datetime.min + horaini).time()
        if isinstance(horafin, timedelta):
            horafin = (datetime.min + horafin).time()
        
        lactancia_info = self.get_lactancia_adjustment(user_id, fecha_marcacion)
        minutos_lactancia = lactancia_info['minutos']
        modo_lactancia = lactancia_info['modo']
        
        if modo_lactancia == 'INICIO':
            tolerancia_total = tolerancia_min + minutos_lactancia
        else:
            tolerancia_total = tolerancia_min
        
        hora_limite_ingreso = (
            datetime.combine(datetime.today(), horaini) + 
            timedelta(minutes=tolerancia_total)
        ).time()
        
        if hora_marcacion < hora_limite_ingreso:
            return "INGRESO"
        elif hora_marcacion >= horafin:
            return "SALIDA"
        else:
            return "INTERMEDIO"
    
    def process_attendance(self, attendance, reloj_id):
        """Procesa una marcación y la muestra en tiempo real"""
        try:
            dni = str(attendance.user_id).zfill(8)
            timestamp = attendance.timestamp
            
            if timestamp.tzinfo is None:
                timestamp = self.timezone.localize(timestamp)
            else:
                timestamp = timestamp.astimezone(self.timezone)
            
            fechahora_str = timestamp.strftime('%Y-%m-%d %H:%M:%S')
            fecha_str = timestamp.strftime('%Y-%m-%d')
            hora_str = timestamp.strftime('%H:%M:%S')
            hora_marcacion = timestamp.time()
            
            # Verificar día laborable
            calendar_info = self.get_calendar_day_info(fecha_str)
            
            # Obtener información del usuario
            user_info = self.get_user_info(dni)
            
            if not calendar_info['is_working']:
                user_id = user_info['user_id'] if user_info else None
                nombre_completo = f"{user_info['nombre']} {user_info['apellidos']}" if user_info else ""
                tipo_marcaje = None
                mensaje = f"Día no laborable - {calendar_info['descripcion']}"
            elif not user_info:
                user_id = None
                nombre_completo = ""
                tipo_marcaje = None
                mensaje = "Usuario no encontrado en sistema"
            else:
                user_id = user_info['user_id']
                nombre_completo = f"{user_info['nombre']} {user_info['apellidos']}"
                
                job_assignments = self.get_validated_job_assignments(user_id, fecha_str)
                
                if not job_assignments:
                    tipo_marcaje = "INTERMEDIO"
                    mensaje = "Sin job assignment activo"
                else:
                    tipo_marcaje = self.classify_attendance_type(
                        hora_marcacion, job_assignments, user_id, fecha_str
                    )
                    job = job_assignments[0]
                    mensaje = f"Cargo: {job['cargo']} | Horario: {job['horaini']}-{job['horafin']}"
            
            # Preparar datos
            attendance_data = {
                'dni': dni,
                'nombre': nombre_completo,
                'fechahora': fechahora_str,
                'fecha': fecha_str,
                'hora': hora_str,
                'reloj': reloj_id,
                'user_id': user_id,
                'tipo_marcaje': tipo_marcaje,
                'mensaje': mensaje,
                'procesado': True,
                'timestamp': timestamp  # Agregar timestamp para comparación
            }
            
            # VERIFICAR SI YA EXISTE (dni, fechahora, reloj)
            is_duplicate = self.check_attendance_exists(dni, fechahora_str, reloj_id)
            
            if is_duplicate:
                self.update_stats(reloj_id, 'duplicates')
                self.update_stats(reloj_id, 'processed')
                
                # ACTUALIZAR ÚLTIMA MARCACIÓN INCLUSO SI ES DUPLICADA
                self.update_last_attendance(reloj_id, attendance_data)
                
                with self.display_lock:
                    print(f"\n⚠️ DUPLICADA    | DNI: {dni} | {fechahora_str} | {reloj_id}")
                    self.display_realtime_stats()
                
                return False  # No insertada pero procesada
            
            # Insertar en BD
            self.insert_attendance(attendance_data)
            
            # Actualizar estadísticas (incluyendo última marcación)
            self.update_stats(reloj_id, 'processed')
            self.update_stats(reloj_id, 'inserted')
            self.update_last_attendance(reloj_id, attendance_data)
            
            if tipo_marcaje:
                with self.stats_lock:
                    self.stats['by_type'][tipo_marcaje] += 1
            
            # Mostrar en tiempo real
            self.display_attendance_realtime(attendance_data)
            
            return True
            
        except Exception as e:
            logger.error(f"Error procesando marcación {dni}: {e}")
            self.update_stats(reloj_id, 'error')
            return False
    
    def insert_attendance(self, attendance_data):
        """Inserta la marcación en la base de datos"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    INSERT INTO attendances (
                        dni, nombre, fechahora, fecha, hora, reloj, 
                        user_id, tipo_marcaje, mensaje, procesado
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                    )
                    """
                    cur.execute(sql, (
                        attendance_data['dni'],
                        attendance_data['nombre'],
                        attendance_data['fechahora'],
                        attendance_data['fecha'],
                        attendance_data['hora'],
                        attendance_data['reloj'],
                        attendance_data['user_id'],
                        attendance_data['tipo_marcaje'],
                        attendance_data['mensaje'],
                        attendance_data['procesado']
                    ))
                    conn.commit()
                    
        except Exception as e:
            logger.error(f"Error insertando marcación en BD: {e}")
            raise
    
    def display_attendance_realtime(self, attendance_data):
        """Muestra la marcación procesada en tiempo real"""
        with self.display_lock:
            tipo_emoji = {
                'INGRESO': '🟢',
                'INTERMEDIO': '🟡',
                'SALIDA': '🔴',
                None: '⚪'
            }
            
            tipo = attendance_data['tipo_marcaje'] or 'SIN_TIPO'
            emoji = tipo_emoji.get(attendance_data['tipo_marcaje'], '⚪')
            
            # Formato compacto pero informativo
            nombre_display = attendance_data['nombre'][:30] if attendance_data['nombre'] else 'Sin nombre'
            
            print(f"\n{emoji} {tipo:12} | DNI: {attendance_data['dni']} | "
                  f"{attendance_data['fechahora']} | {attendance_data['reloj']} | "
                  f"{nombre_display}")
            
            # Mostrar estadísticas actualizadas
            self.display_realtime_stats()
    
    def sync_clock_all_attendances(self, zk_config, reloj_id):
        """Sincroniza TODAS las marcaciones de un reloj"""
        try:
            with self.display_lock:
                print(f"\n{'='*80}")
                print(f"🔄 INICIANDO SINCRONIZACIÓN: {reloj_id}")
                print(f"{'='*80}")
            
            # Obtener TODAS las marcaciones
            attendances = self.get_all_clock_attendances(zk_config, reloj_id)
            
            if not attendances:
                with self.display_lock:
                    print(f"⚠️ {reloj_id}: No se obtuvieron marcaciones")
                return 0
            
            # Procesar cada marcación
            processed_count = 0
            for attendance in attendances:
                if self.process_attendance(attendance, reloj_id):
                    processed_count += 1
            
            with self.display_lock:
                print(f"\n{'='*80}")
                print(f"✅ {reloj_id}: {processed_count}/{len(attendances)} marcaciones procesadas")
                print(f"{'='*80}")
            
            return processed_count
            
        except Exception as e:
            logger.error(f"Error sincronizando {reloj_id}: {e}")
            return 0
    
    def sync_all_clocks(self, relojes_config):
        """Sincroniza todos los relojes con procesamiento paralelo"""
        print("\n" + "="*80)
        print("🚀 SINCRONIZACIÓN COMPLETA - TODAS LAS MARCACIONES")
        print("="*80)
        
        start_time = time.time()
        max_workers = self.connection_config['max_workers']
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_reloj = {
                executor.submit(self.sync_clock_all_attendances, zk_config, reloj_id): reloj_id
                for reloj_id, zk_config in relojes_config.items()
            }
            
            for future in as_completed(future_to_reloj):
                reloj_id = future_to_reloj[future]
                try:
                    future.result()
                except Exception as e:
                    logger.error(f"❌ Error en {reloj_id}: {e}")
        
        elapsed_time = time.time() - start_time
        
        # Resumen final
        self.display_final_summary(elapsed_time)
    
    def display_final_summary(self, elapsed_time):
        """Muestra el resumen final de la sincronización"""
        print("\n" + "="*80)
        print("📊 RESUMEN FINAL DE SINCRONIZACIÓN")
        print("="*80)
        
        with self.stats_lock:
            print(f"\n📥 Total marcaciones obtenidas: {self.stats['total_fetched']}")
            print(f"✅ Total procesadas: {self.stats['total_processed']}")
            print(f"💾 Total insertadas en BD: {self.stats['total_inserted']}")
            print(f"🔄 Total duplicadas (omitidas): {self.stats['total_duplicates']}")
            print(f"❌ Total errores: {self.stats['total_errors']}")
            
            print(f"\n⏱️ Tiempo transcurrido: {elapsed_time:.2f} segundos")
            
            if self.stats['total_processed'] > 0:
                print(f"⚡ Velocidad: {self.stats['total_processed']/elapsed_time:.2f} marcaciones/segundo")
            
            print(f"\n📍 Detalle por reloj:")
            for clock_id in sorted(self.stats['by_clock'].keys()):
                clock_stats = self.stats['by_clock'][clock_id]
                print(f"  {clock_id}: Obtenidas={clock_stats['fetched']}, "
                      f"Procesadas={clock_stats['processed']}, "
                      f"Insertadas={clock_stats['inserted']}, "
                      f"Duplicadas={clock_stats['duplicates']}")
            
            if self.stats['by_type']:
                print(f"\n🎯 Marcaciones por tipo:")
                for tipo, count in sorted(self.stats['by_type'].items()):
                    print(f"  {tipo}: {count}")
            
            # MOSTRAR ÚLTIMA MARCACIÓN DE CADA RELOJ (INSERTADA O DUPLICADA)
            print(f"\n🕐 ÚLTIMA MARCACIÓN PROCESADA POR RELOJ:")
            print("-" * 80)
            for clock_id in sorted(self.stats['by_clock'].keys()):
                last_att = self.stats['by_clock'][clock_id]['last_attendance']
                if last_att:
                    tipo_emoji = {
                        'INGRESO': '🟢',
                        'INTERMEDIO': '🟡',
                        'SALIDA': '🔴',
                        None: '⚪'
                    }
                    tipo = last_att['tipo_marcaje'] or 'SIN_TIPO'
                    emoji = tipo_emoji.get(last_att['tipo_marcaje'], '⚪')
                    nombre_display = last_att['nombre'][:30] if last_att['nombre'] else 'Sin nombre'
                    
                    print(f"\n{clock_id}:")
                    print(f"  {emoji} {tipo:12} | DNI: {last_att['dni']} | "
                          f"{last_att['fechahora']} | {nombre_display}")
                    if last_att.get('mensaje'):
                        print(f"  ℹ️  {last_att['mensaje']}")
                else:
                    print(f"\n{clock_id}: Sin marcaciones procesadas")
            print("-" * 80)
        
        print("="*80)
        print("✨ SINCRONIZACIÓN COMPLETADA")
        print("="*80 + "\n")


def main():
    """Función principal"""
    # Configuración de base de datos
    db_config = {
        'host': '172.16.1.61',
        'port': 5432,
        'user': 'nestor',
        'password': 'Arequipa@2018',
        'database': "asistenciaV2r",
    }
    
    # Configuración de relojes
    relojes_config = {
        'reloj1': {
            'ip': '172.16.250.3',
            'port': 4370
        },
        'reloj2': {
            'ip': '172.16.250.4',
            'port': 4370
        }
    }
    
    # Crear sincronizador
    sync = RealtimeAttendanceSync(db_config)
    
    try:
        # Sincronizar todos los relojes
        sync.sync_all_clocks(relojes_config)
        
    except KeyboardInterrupt:
        print("\n⚠️ Sincronización interrumpida por el usuario")
    except Exception as e:
        logger.error(f"💥 Error en sincronización: {e}")
        print(f"❌ Error: {e}")


if __name__ == "__main__":
    main()
