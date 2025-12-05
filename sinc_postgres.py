# -*- coding: utf-8 -*-  
import sys
sys.path.append("zk")
from datetime import datetime
import psycopg2
from zk import ZK, const
import datetime as dt
import pytz as tz
import logging
import argparse
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('biometric_sync_improved.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class BiometricSync:
    def __init__(self, db_config, email_config=None):
        self.db_config = db_config
        self.email_config = email_config
        self.timezone = tz.timezone('America/Lima')
        
    def get_db_connection(self):
        """Establece conexión a la base de datos"""
        try:
            conn = psycopg2.connect(**self.db_config)
            return conn
        except Exception as e:
            logger.error("Error conectando a la base de datos: {}".format(e))
            raise
    
    def get_last_sync_timestamp(self, reloj_id):
        """Obtiene el timestamp del último registro sincronizado para este reloj"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT MAX(fechahora) 
                    FROM attendances 
                    WHERE reloj = %s
                    """
                    cur.execute(sql, (reloj_id,))
                    result = cur.fetchone()
                    
                    if result and result[0]:
                        # Convertir a datetime si es string
                        if isinstance(result[0], str):
                            dt_naive = datetime.strptime(result[0], '%Y-%m-%d %H:%M')
                            # Convertir a timezone aware
                            return self.timezone.localize(dt_naive)
                        elif hasattr(result[0], 'tzinfo') and result[0].tzinfo is None:
                            # Si es datetime pero naive, convertir a aware
                            return self.timezone.localize(result[0])
                        else:
                            # Si ya tiene timezone, convertir al timezone local
                            return result[0].astimezone(self.timezone) if result[0].tzinfo else self.timezone.localize(result[0])
                    return None
        except Exception as e:
            logger.error("Error obteniendo último timestamp: {}".format(e))
            return None
    
    def record_exists(self, dni, fecha_hora, reloj_id):
        """Verifica si ya existe un registro específico"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT 1 FROM attendances 
                    WHERE dni = %s AND fechahora = %s AND reloj = %s
                    LIMIT 1
                    """
                    cur.execute(sql, (dni, fecha_hora, reloj_id))
                    return cur.fetchone() is not None
        except Exception as e:
            logger.error("Error verificando existencia de registro: {}".format(e))
            return True  # En caso de error, asumimos que existe para evitar duplicados
    
    def insert_attendance(self, attendance_data):
        """Inserta un nuevo registro de asistencia"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    INSERT INTO attendances (dni, nombre, fechahora, fecha, hora, reloj, created_at, updated_at) 
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """
                    cur.execute(sql, attendance_data)
                    conn.commit()
                    return True
        except Exception as e:
            logger.error("Error insertando registro: {}".format(e))
            return False
    
    def get_user_email(self, dni):
        """Obtiene el email del usuario a partir de su DNI"""
        try:
            with self.get_db_connection() as conn:
                with conn.cursor() as cur:
                    sql = """
                    SELECT email FROM users 
                    WHERE dni = %s AND email IS NOT NULL AND email != ''
                    LIMIT 1
                    """
                    cur.execute(sql, (dni,))
                    result = cur.fetchone()
                    return result[0] if result else None
        except Exception as e:
            logger.error("Error obteniendo email del usuario: {}".format(e))
            return None
    
    def send_email_notification(self, email, nombre, fecha_hora, reloj_id):
        """Envía un correo electrónico al usuario con su marcación"""
        if not self.email_config or not email:
            return False
        
        try:
            msg = MIMEMultipart()
            msg['From'] = self.email_config['from_email']
            msg['To'] = email
            msg['Subject'] = "Nueva marcación registrada"
            
            body = f"""Hola {nombre},
            
            Se ha registrado una nueva marcación con los siguientes datos:
            
            Fecha y hora: {fecha_hora}
            Reloj: {reloj_id}
            
            Este es un mensaje automático, por favor no responda a este correo.
            
            Saludos,
            Sistema de Control de Asistencia
            """
            
            msg.attach(MIMEText(body, 'plain'))
            
            server = smtplib.SMTP(self.email_config['smtp_server'], self.email_config['smtp_port'])
            server.starttls()
            server.login(self.email_config['username'], self.email_config['password'])
            server.send_message(msg)
            server.quit()
            
            logger.info(f"Correo enviado a {email} para la marcación {fecha_hora}")
            return True
        except Exception as e:
            logger.error(f"Error enviando correo a {email}: {e}")
            return False
    
    def sync_biometric_data(self, zk_config, reloj_id):
        """Sincroniza datos del reloj biométrico con la base de datos"""
        stats = {
            'total_records': 0,
            'new_records': 0,
            'duplicates': 0,
            'errors': 0,
            'emails_sent': 0,
            'last_record': None
        }
        
        zk = ZK(
            zk_config['ip'], 
            port=zk_config['port'], 
            timeout=zk_config['timeout'],
            password=zk_config['password'],
            force_udp=zk_config.get('force_udp', False),
            ommit_ping=zk_config.get('ommit_ping', False)
        )
        
        conn = None
        
        try:
            logger.info(f'Conectando a dispositivo {reloj_id} ({zk_config["ip"]})...')
            conn = zk.connect()
            
            logger.info('Deshabilitando dispositivo...')
            conn.disable_device()
            
            logger.info('Versión de firmware: {}'.format(conn.get_firmware_version()))
            
            # Obtener último timestamp sincronizado
            last_sync = self.get_last_sync_timestamp(reloj_id)
            logger.info('Último registro sincronizado: {}'.format(last_sync))
            
            # Obtener todos los usuarios para mapear ID a nombre
            users = conn.get_users()
            user_names = {str(user.user_id): user.name for user in users}
            logger.info('Total de usuarios en el reloj: {}'.format(len(users)))
            
            # Obtener todas las asistencias
            attendances = conn.get_attendance()
            stats['total_records'] = len(attendances)
            
            logger.info('Total de registros en el reloj: {}'.format(stats["total_records"]))
            
            # Obtener timestamp actual
            ahora = tz.utc.localize(dt.datetime.utcnow()).astimezone(self.timezone)
            
            # Encontrar el último registro del reloj (el más reciente)
            latest_attendance = None
            latest_timestamp = None
            
            # Filtrar registros más recientes que el último sincronizado
            filtered_attendances = []
            for asistencia in attendances:
                try:
                    # Convertir timestamp a timezone local
                    attendance_time = asistencia.timestamp
                    if attendance_time.tzinfo is None:
                        attendance_time = self.timezone.localize(attendance_time)
                    else:
                        attendance_time = attendance_time.astimezone(self.timezone)
                    
                    # Solo procesar registros más recientes que el último sincronizado
                    if last_sync and attendance_time <= last_sync:
                        stats['duplicates'] += 1
                        continue
                    
                    filtered_attendances.append((asistencia, attendance_time))
                    
                    # Actualizar el último registro si es más reciente
                    if latest_timestamp is None or attendance_time > latest_timestamp:
                        latest_timestamp = attendance_time
                        latest_attendance = asistencia
                except Exception as e:
                    logger.error('Error procesando timestamp de asistencia {}: {}'.format(asistencia.user_id, e))
                    stats['errors'] += 1
            
            logger.info('Registros a procesar después de filtrar por fecha: {}'.format(len(filtered_attendances)))
            
            # Procesar los registros filtrados
            for asistencia, attendance_time in filtered_attendances:
                try:
                    # Formatear datos
                    fecha_hora = attendance_time.strftime('%Y-%m-%d %H:%M')
                    fecha = attendance_time.strftime('%Y-%m-%d')
                    hora = attendance_time.strftime('%H:%M')
                    
                    # Verificar si el registro ya existe (doble verificación)
                    if self.record_exists(str(asistencia.user_id), fecha_hora, reloj_id):
                        stats['duplicates'] += 1
                        logger.debug('Registro duplicado: DNI {} - {}'.format(asistencia.user_id, fecha_hora))
                        continue
                    
                    # Obtener el nombre del usuario si existe
                    nombre = user_names.get(str(asistencia.user_id), '')
                    
                    # Insertar nuevo registro
                    attendance_data = (
                        str(asistencia.user_id),
                        nombre,
                        fecha_hora,
                        fecha,
                        hora,
                        reloj_id,
                        ahora,
                        ahora
                    )
                    
                    if self.insert_attendance(attendance_data):
                        stats['new_records'] += 1
                        logger.info('Nuevo registro: DNI {} - {} - {}'.format(asistencia.user_id, nombre, fecha_hora))
                        
                        # Enviar correo electrónico si está configurado
                        if self.email_config:
                            email = self.get_user_email(str(asistencia.user_id))
                            if email:
                                if self.send_email_notification(email, nombre, fecha_hora, reloj_id):
                                    stats['emails_sent'] += 1
                    else:
                        stats['errors'] += 1
                        
                except Exception as e:
                    logger.error('Error procesando asistencia {}: {}'.format(asistencia.user_id, e))
                    stats['errors'] += 1
            
            # Guardar información del último registro
            if latest_attendance:
                latest_time = latest_timestamp.strftime('%Y-%m-%d %H:%M')
                latest_date = latest_timestamp.strftime('%Y-%m-%d')
                latest_hour = latest_timestamp.strftime('%H:%M')
                
                # Obtener el nombre del último usuario
                latest_nombre = user_names.get(str(latest_attendance.user_id), '')
                
                stats['last_record'] = {
                    'dni': str(latest_attendance.user_id),
                    'nombre': latest_nombre,
                    'fechahora': latest_time,
                    'fecha': latest_date,
                    'hora': latest_hour
                }
                
                logger.info('Último registro del reloj: DNI {} - {} - {}'.format(
                    latest_attendance.user_id, latest_nombre, latest_time))
            
            logger.info('Habilitando dispositivo...')
            conn.enable_device()
            
        except Exception as e:
            logger.error('Error en el proceso de sincronización: {}'.format(e))
            stats['errors'] += 1
            
        finally:
            if conn:
                try:
                    conn.disconnect()
                    logger.info('Desconectado del dispositivo')
                except:
                    pass
        
        return stats

def main():
    # Agregar parser de argumentos
    parser = argparse.ArgumentParser(description='Sincronización de relojes biométricos')
    parser.add_argument('--send-emails', action='store_true', help='Enviar correos electrónicos con las marcaciones')
    args = parser.parse_args()
    
    # Configuración de la base de datos
    db_config = {
        'host': "172.16.120.100",
        'database': "beezeP",
        'user': "nestor",
        'password': "Arequipa@2018"
    }
    
    # Configuración de correo electrónico (opcional)
    email_config = None
    if args.send_emails:
        email_config = {
            'smtp_server': 'sandbox.smtp.mailtrap.io',  # Servidor SMTP de Mailtrap
            'smtp_port': 2525,                         # Puerto SMTP de Mailtrap
            'username': 'f93581fde0a730',              # Usuario de Mailtrap
            'password': 'b409ea1ace6b3c',              # Contraseña de Mailtrap
            'from_email': 'sistema@tuempresa.com',     # Correo del remitente
            'use_tls': True                            # Habilitar encriptación TLS
        }
    
    # Configuración de los relojes biométricos
    relojes = [
        {
            'id': 'reloj1',
            'config': {
                'ip': '172.16.250.3',
                'port': 4370,
                'timeout': 5,
                'password': 0,
                'force_udp': False,
                'ommit_ping': False
            }
        },
        {
            'id': 'reloj2',
            'config': {
                'ip': '172.16.250.4',
                'port': 4370,
                'timeout': 5,
                'password': 0,
                'force_udp': False,
                'ommit_ping': False
            }
        }
    ]
    
    # Crear instancia del sincronizador
    sync = BiometricSync(db_config, email_config)
    
    # Resultados globales
    total_stats = {
        'total_records': 0,
        'new_records': 0,
        'duplicates': 0,
        'errors': 0,
        'emails_sent': 0
    }
    
    # Sincronizar cada reloj
    for reloj in relojes:
        print(f'\nIniciando sincronización de {reloj["id"]}...')
        stats = sync.sync_biometric_data(reloj['config'], reloj['id'])
        
        # Mostrar estadísticas para este reloj
        print(f'=== RESUMEN DE SINCRONIZACIÓN DE {reloj["id"]} ===')
        print('Total de registros en reloj: {}'.format(stats["total_records"]))
        print('Nuevos registros insertados: {}'.format(stats["new_records"]))
        print('Registros duplicados omitidos: {}'.format(stats["duplicates"]))
        print('Correos electrónicos enviados: {}'.format(stats.get("emails_sent", 0)))
        print('Errores: {}'.format(stats["errors"]))
        
        # Mostrar información del último registro
        if stats.get('last_record'):
            last_record = stats['last_record']
            print('\n=== ÚLTIMO REGISTRO DEL RELOJ ===')
            print('DNI: {}'.format(last_record['dni']))
            print('Nombre: {}'.format(last_record['nombre']))
            print('Fecha y hora: {}'.format(last_record['fechahora']))
            print('Fecha: {}'.format(last_record['fecha']))
            print('Hora: {}'.format(last_record['hora']))
        
        # Acumular estadísticas globales
        total_stats['total_records'] += stats['total_records']
        total_stats['new_records'] += stats['new_records']
        total_stats['duplicates'] += stats['duplicates']
        total_stats['errors'] += stats['errors']
        total_stats['emails_sent'] += stats.get('emails_sent', 0)
    
    # Mostrar estadísticas globales
    print('\n=== RESUMEN GLOBAL DE SINCRONIZACIÓN ===')
    print('Total de registros en relojes: {}'.format(total_stats["total_records"]))
    print('Nuevos registros insertados: {}'.format(total_stats["new_records"]))
    print('Registros duplicados omitidos: {}'.format(total_stats["duplicates"]))
    print('Correos electrónicos enviados: {}'.format(total_stats["emails_sent"]))
    print('Errores: {}'.format(total_stats["errors"]))
    
    print('\nSincronización completada.')

if __name__ == "__main__":
    main()


