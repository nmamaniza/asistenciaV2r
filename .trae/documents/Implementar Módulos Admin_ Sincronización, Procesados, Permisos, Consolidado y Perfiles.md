## Alcance
- Unificar el menú/submenú de administración en todas las páginas.
- Añadir funcionalidad completa en: Sincronización, Procesados, Permisos, Consolidado y Perfiles.
- Integrar ejecución de scripts y vistas con OpenUI5, asegurando autenticación existente (Spring Security).

## Submenú Común
- Reutilizar cabecera y dropdown del admin en `dashboard_admin.html` para: `dashboard_admin.html`, `biometric_sync.html`, `procesados.html`, `permisos.html`, `consolidado.html`, `perfil.html`.
- Normalizar rutas relativas (`/asistenciaV2r/...`) y etiquetas.

## Backend: Endpoints
- **Sincronización**: ya existe `/api/biometric-sync` (SSE, start/stream/status). Mantener y aplicar submenú.
- **Procesados**:
  - `ProcessAttendanceServlet` en `/api/process-attendance` con acciones:
    - `action=startScript` (params: `fechaInicio`, `fechaFin`, `dni`), invoca `procesarAsistencia.py` con esos parámetros (similar a `BiometricSyncServlet`).
    - `action=stream` SSE para la salida en tiempo real.
    - `action=status` para estado del proceso.
  - `ProcessedDataServlet` en `/api/processed-data`:
    - `GET` con filtros `mes`, `anio`, `dni`/`nombre` para listar registros procesados.
    - Query basada en `dailyattendances` y join con `users`/`jobassignments` o vista `vw_resumen_asistencia` (si disponible). Campos: `id, dni, modalidad (horario o cargo/area), nombre, fecha, obs, doc, final, horaint`.
  - `UpdateDailyAttendanceServlet` en `/api/processed-update` `POST` para actualizar `doc` y `final` (similar a `src/main/java/com/asistenciav2/servlet/UpdateAttendanceServlet.java`, pero usando tabla `dailyattendances` y validando `estado=1`).
- **Permisos**:
  - `PermissionsServlet` en `/api/permissions`:
    - `GET` lista permisos activos con joins: `permissions`, `permissiontypes`, `lactation_schedules`.
    - `POST` crear permiso (tipos: `LSG` y `LACTANCIA`), con fechas (`fechaini`, `fechafin`) y estado.
    - `PUT` actualizar estado/fechas.
  - `LactationSchedulesServlet` en `/api/lactation-schedules`:
    - `POST` crear/actualizar horarios de lactancia (`modo` INICIO/FIN, `minutos_diarios`, rango de fechas, `estado`).
  - Usar estructura SQL de `asistenciaV3vc_mejorado.sql` para asegurar integridad (FKs, tipos, checks).
- **Consolidado**:
  - `ConsolidatedReportServlet` en `/api/consolidated` `GET` con filtros `mes`, `anio`, `dni`/`nombre`.
  - Consultar `vw_resumen_asistencia` o construir agregación sobre `dailyattendances`/`users` para obtener por mes y mostrar campo `final`.
- **Perfiles**:
  - `UsersServlet` en `/api/users`:
    - `GET` listar usuarios con filtros.
    - `POST` crear usuario (hash de password con jBCrypt, `role`, `estado`).
    - `PUT` actualizar datos del usuario (nombre, apellidos, email, teléfono, dirección, estado).
    - Validar unicidad de `dni` y `email` según esquema.

## Frontend: OpenUI5
- **Sincronización** (`biometric_sync.html`):
  - Insertar submenú admin.
  - Mantener tabla de últimos registros.
- **Procesados** (`procesados.html`):
  - Panel de parámetros: DatePicker para `--fecha-inicio`, `--fecha-fin`; `Input` para `dni`.
  - Botón "Procesar" que llama `/api/process-attendance?action=startScript&...` y muestra salida SSE.
  - Grilla de resultados (`sap.m.Table`) con edición inline de `doc` y `final`:
    - Al modificar, enviar `POST` a `/api/processed-update`.
  - Filtros arriba por mes/año, DNI/Nombre (usar `sap.m.SearchField` y `Select`).
- **Permisos** (`permisos.html`):
  - Formulario para crear permiso LSG y Lactancia:
    - Campos: usuario (DNI búsqueda), tipo (`LSG`/`LACTANCIA`), fechas (`fechaini`, `fechafin`), descripción.
    - Para Lactancia: `modo (INICIO/FIN)`, `minutos_diarios`, `fecha_desde`, `fecha_hasta`.
  - Tabla de permisos con estado y acciones (aprobar, rechazar, editar).
- **Consolidado** (`consolidado.html`):
  - Filtros: mes, año, DNI/nombre.
  - Tabla con columnas clave del consolidado y el campo `final` destacado.
  - Resúmenes (cards) para totales por estado `final` y horas/minutos.
- **Perfiles** (`perfil.html`):
  - Lista de usuarios (tabla) + formulario de creación/edición.
  - Validaciones básicas (email, DNI único). Cambio de contraseña con hash jBCrypt.

## Consultas y Datos
- **Procesados**:
  - Base: `dailyattendances` con joins:
    - `JOIN jobassignments ja ON ja.id = dailyattendances.jobassignment_id`
    - `JOIN users u ON u.id = ja.user_id`
  - Campos requeridos según pedido; "modalidad" puede ser `cargo/area` o `workschedules.descripcion` según disponibilidad.
- **Consolidado**:
  - Preferir `vw_resumen_asistencia` (existe en `asistenciaV3vc_mejorado.sql`) para rendimiento y consistencia.
- **Permisos**:
  - Usar `permissiontypes` para validar códigos (`LSG`, `LACTANCIA`).
  - CRUD con integridad de fechas y estados.

## Seguridad y Roles
- Proteger endpoints con Spring Security (ya presente), permitiendo acceso solo a rol administrador.
- Evitar exponer ejecución de scripts a usuarios no autorizados.

## Validación y UX
- Retroalimentación con `sap.m.MessageToast` y `sap.m.Dialog` para errores/confirmaciones.
- SSE para procesos largos (procesar asistencias, sincronización).
- Editor inline de `doc` y `final` con guardado por fila.

## Entregables
- Nuevos Servlets: `ProcessAttendanceServlet`, `ProcessedDataServlet`, `UpdateDailyAttendanceServlet`, `PermissionsServlet`, `LactationSchedulesServlet`, `ConsolidatedReportServlet`, `UsersServlet`.
- Actualizaciones de HTML: submenú admin + contenido UI5 en `biometric_sync.html`, `procesados.html`, `permisos.html`, `consolidado.html`, `perfil.html`.
- Consultas SQL/uso de vista `vw_resumen_asistencia`.

## Confirmación
- Tras tu confirmación, implemento los servlets y las vistas UI5, integro el submenú común, y verifico end-to-end con datos reales (incluye ejecución de `procesarAsistencia.py` desde la UI de Procesados).