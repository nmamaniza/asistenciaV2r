## Objetivo
- Unificar el submenú (dropdown de navegación) en todas las páginas admin con rutas absolutas bajo `/asistenciaV2r/`, coherente y reutilizable.

## Páginas Alcanzadas
- `dashboard_admin.html`
- `biometric_sync.html`
- `procesados.html`
- `permisos.html`
- `consolidado.html`
- `perfil.html`

## Estandarización del Submenú
- Encabezado: texto `Administrador`.
- Entradas del menú (rutas absolutas):
  - `🏠 Dashboard Admin` → `/asistenciaV2r/dashboard_admin.html`
  - `🔄 Sincronización` → `/asistenciaV2r/biometric_sync.html`
  - `📋 Procesados` → `/asistenciaV2r/procesados.html`
  - `🔐 Permisos` → `/asistenciaV2r/permisos.html`
  - `📊 Consolidado` → `/asistenciaV2r/consolidado.html`
  - `👤 Perfil` → `/asistenciaV2r/perfil.html`
  - `🚪 Cerrar Sesión` → `/asistenciaV2r/logout`
- Mantener comportamiento: `toggleDropdown()` y cierre al clicar fuera.

## Implementación Técnica
- Reemplazar en cada archivo el bloque `<div class="dropdown-menu" id="dropdownMenu">...</div>` por el bloque estándar con rutas absolutas y encabezado `Administrador`.
- Alinear estilos (`dropdown-menu`, `dropdown-item`, `dropdown-header`, `logout`) ya presentes.
- Verificar avatar y header: usar la primera letra del nombre del usuario si el endpoint `userInfo` está disponible; fallback a `A`.

## Verificación
- Abrir cada página y validar que el submenú:
  - Se despliega y cierra correctamente.
  - Navega a las páginas esperadas con URLs absolutas `/asistenciaV2r/...`.
- Prueba de acceso controlado: confirmar que páginas requieren autenticación según la configuración actual de seguridad.

## Entregables
- Actualizaciones en los 6 archivos HTML para el submenú unificado.
- Confirmación de navegación correcta entre módulos desde cualquier página admin.

## Confirmación
- Tras aprobación, procedo a realizar las ediciones en los 6 archivos y validarlas en el navegador.