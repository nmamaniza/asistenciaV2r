#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script de prueba para verificar el manejo de permisos en procesarAsistencia.py
"""

import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime

# Configuración de conexión
DB_CONFIG = {
    'dbname': 'asistenciaV2r',
    'user': 'nestor',
    'password': 'Arequipa@2018',
    'host': '172.16.1.61',
    'port': 5432
}

def test_permisos():
    """Prueba la obtención de permisos"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        print("=" * 80)
        print("PRUEBA DE CONSULTA DE PERMISOS")
        print("=" * 80)
        
        # Obtener algunos usuarios con permisos
        cursor.execute("""
            SELECT DISTINCT 
                u.id, 
                u.dni, 
                u.nombre, 
                u.apellidos
            FROM users u
            INNER JOIN permissions p ON p.user_id = u.id
            WHERE p.estado = 1
            LIMIT 5
        """)
        
        usuarios = cursor.fetchall()
        
        if not usuarios:
            print("\n⚠️  No se encontraron usuarios con permisos activos")
            return
        
        print(f"\n✓ Se encontraron {len(usuarios)} usuarios con permisos activos\n")
        
        for usuario in usuarios:
            print(f"\n{'─' * 80}")
            print(f"Usuario: {usuario['nombre']} {usuario['apellidos']} (DNI: {usuario['dni']})")
            print(f"{'─' * 80}")
            
            # Obtener permisos del usuario
            cursor.execute("""
                SELECT 
                    p.id,
                    p.abrevia,
                    p.fechaini,
                    p.fechafin,
                    pt.codigo as tipo_codigo,
                    pt.descripcion as tipo_descripcion
                FROM permissions p
                INNER JOIN permissiontypes pt ON pt.id = p.permissiontype_id
                WHERE p.user_id = %s
                AND p.estado = 1
                ORDER BY p.fechaini DESC
            """, (usuario['id'],))
            
            permisos = cursor.fetchall()
            
            if permisos:
                print(f"\nPermisos activos: {len(permisos)}")
                for permiso in permisos:
                    print(f"  • {permiso['tipo_codigo']:15} | {permiso['abrevia']:5} | "
                          f"{permiso['fechaini']} → {permiso['fechafin']} | "
                          f"{permiso['tipo_descripcion']}")
                    
                    # Si es lactancia, mostrar programación
                    if permiso['tipo_codigo'] == 'LACTANCIA':
                        cursor.execute("""
                            SELECT 
                                fecha_desde,
                                fecha_hasta,
                                modo,
                                minutos_diarios
                            FROM lactation_schedules
                            WHERE permission_id = %s
                            AND estado = 1
                            ORDER BY fecha_desde
                        """, (permiso['id'],))
                        
                        programaciones = cursor.fetchall()
                        if programaciones:
                            print(f"    Programaciones de lactancia:")
                            for prog in programaciones:
                                print(f"      - {prog['fecha_desde']} → {prog['fecha_hasta']}: "
                                      f"Modo {prog['modo']}, {prog['minutos_diarios']} min/día")
            else:
                print("  Sin permisos activos")
        
        print(f"\n{'=' * 80}")
        print("RESUMEN DE TIPOS DE PERMISOS EN EL SISTEMA")
        print(f"{'=' * 80}")
        
        cursor.execute("""
            SELECT 
                pt.id,
                pt.codigo,
                pt.descripcion,
                COUNT(p.id) as total_permisos
            FROM permissiontypes pt
            LEFT JOIN permissions p ON p.permissiontype_id = pt.id AND p.estado = 1
            GROUP BY pt.id, pt.codigo, pt.descripcion
            ORDER BY pt.id
        """)
        
        tipos = cursor.fetchall()
        
        print(f"\n{'ID':<5} {'CÓDIGO':<15} {'DESCRIPCIÓN':<40} {'PERMISOS ACTIVOS':<20}")
        print("─" * 80)
        for tipo in tipos:
            print(f"{tipo['id']:<5} {tipo['codigo']:<15} {tipo['descripcion']:<40} {tipo['total_permisos']:<20}")
        
        print(f"\n{'=' * 80}\n")
        
        conn.close()
        
    except Exception as e:
        print(f"\n❌ Error: {e}")

if __name__ == '__main__':
    test_permisos()
