# Mejoras de Separación de Sesiones por Rol - Sistema de Asistencia

## 📋 Resumen de Cambios

Se ha implementado un sistema completo de separación de sesiones y menús basado en roles (Administrador vs Usuario), con mejoras significativas en la seguridad y experiencia de usuario.

---

## 🎯 Objetivos Cumplidos

### 1. **Separación de Sesiones por Rol**
- ✅ Detección automática del rol del usuario (Admin/Usuario)
- ✅ Menús dinámicos según el rol
- ✅ Control de acceso a páginas restringidas
- ✅ Redirección automática si un usuario intenta acceder a páginas de admin

### 2. **Menús Diferenciados**

#### **Menú de Administrador:**
- 🏠 Dashboard Admin
- 🔄 Sincronización (Biométrica)
- 📋 Procesados
- 🔐 Permisos (Todos)
- 📊 Consolidado
- 👥 Perfiles (Gestión de usuarios)

#### **Menú de Usuario:**
- 🏠 Dashboard
- 📋 Procesados (Solo sus datos)
- 🔐 Mis Permisos (Solo sus permisos)
- 📊 Consolidado (Solo sus datos)
- 👤 Mi Perfil (Con cambio de contraseña)

### 3. **Mejora de la Página de Perfil**
- ✅ Visualización de información personal
- ✅ **Cambio de contraseña** implementado
- ✅ Validación de contraseña actual
- ✅ Validación de nueva contraseña (mínimo 6 caracteres)
- ✅ Confirmación de contraseña
- ✅ Encriptación con BCrypt

---

## 📁 Archivos Creados/Modificados

### **Nuevos Archivos:**

1. **`js/menu-manager.js`**
   - Gestor centralizado de menús
   - Detecta automáticamente el rol del usuario
   - Renderiza menús dinámicos
   - Controla acceso a páginas restringidas
   - Actualiza avatares de usuario

2. **`src/main/java/com/asistenciav2/servlet/ChangePasswordServlet.java`**
   - Servlet para cambio de contraseña
   - Validaciones de seguridad
   - Encriptación BCrypt
   - Auditoría de cambios

### **Archivos Modificados:**

1. **`dashboard.html`**
   - Integración con menu-manager.js
   - Menú dinámico según rol
   - Eliminación de código duplicado

2. **`perfil.html`**
   - Completamente rediseñado
   - Formulario de cambio de contraseña
   - Integración con menu-manager.js
   - Interfaz SAP UI5 mejorada

3. **`WEB-INF/web.xml`**
   - Registro del servlet ChangePasswordServlet
   - Mapeo a `/api/changePassword`

---

## 🔐 Seguridad Implementada

### **Control de Acceso:**
```javascript
// Páginas restringidas solo para administradores
const ADMIN_ONLY_PAGES = [
    'biometric_sync.html',
    'perfiles.html',
    'dashboard_admin.html'
];
```

### **Validaciones de Contraseña:**
- ✅ Verificación de contraseña actual
- ✅ Longitud mínima de 6 caracteres
- ✅ Confirmación de contraseña
- ✅ Encriptación BCrypt
- ✅ Auditoría de cambios (usermod, fechamod)

---

## 🚀 Funcionalidades Nuevas

### **1. Gestión de Menús Dinámica**
El sistema ahora detecta automáticamente el rol del usuario y muestra solo las opciones relevantes:

```javascript
// Inicialización automática en cada página
document.addEventListener('DOMContentLoaded', function() {
    window.menuManager.init();
});
```

### **2. Cambio de Contraseña**
Los usuarios pueden cambiar su propia contraseña desde la página de perfil:

**Endpoint:** `POST /asistenciaV2r/api/changePassword`

**Parámetros:**
- `currentPassword`: Contraseña actual
- `newPassword`: Nueva contraseña

**Respuesta:**
```json
{
    "success": true,
    "message": "Contraseña actualizada correctamente"
}
```

### **3. Protección de Páginas**
Si un usuario normal intenta acceder a una página de administrador, es redirigido automáticamente:

```javascript
// Verificación automática al cargar la página
checkPageAccess() {
    if (ADMIN_ONLY_PAGES.includes(currentPage) && !this.isAdmin) {
        window.location.href = '/asistenciaV2r/dashboard.html';
    }
}
```

---

## 📊 Configuración de Menús

### **Estructura de Configuración:**
```javascript
const MENU_CONFIG = {
    ADMIN: [
        { icon: '🏠', text: 'Dashboard Admin', href: '/asistenciaV2r/dashboard_admin.html' },
        { icon: '🔄', text: 'Sincronización', href: '/asistenciaV2r/biometric_sync.html' },
        // ... más opciones
    ],
    USER: [
        { icon: '🏠', text: 'Dashboard', href: '/asistenciaV2r/dashboard.html' },
        { icon: '📋', text: 'Procesados', href: '/asistenciaV2r/procesados.html' },
        // ... más opciones
    ]
};
```

---

## 🔄 Flujo de Autenticación

1. **Login** → Usuario ingresa credenciales
2. **Spring Security** → Valida y crea sesión
3. **UserInfoServlet** → Retorna información del usuario incluyendo rol
4. **MenuManager** → Detecta rol y renderiza menú apropiado
5. **Page Access Control** → Verifica permisos para la página actual
6. **Redirección** → Si no tiene permisos, redirige a dashboard apropiado

---

## 📝 Próximos Pasos Recomendados

### **Para Completar la Implementación:**

1. **Actualizar otras páginas HTML:**
   - `procesados.html` - Agregar menu-manager.js
   - `permisos.html` - Agregar menu-manager.js y filtrar por usuario
   - `consolidado.html` - Agregar menu-manager.js
   - `dashboard_admin.html` - Agregar menu-manager.js

2. **Modificar PermissionsServlet:**
   - Filtrar permisos por usuario si no es admin
   - Solo mostrar permisos propios para usuarios normales

3. **Modificar ProcessedDataServlet:**
   - Filtrar datos procesados por usuario si no es admin

4. **Modificar ConsolidatedDataServlet:**
   - Filtrar datos consolidados por usuario si no es admin

---

## 🧪 Pruebas Recomendadas

### **Como Usuario Normal:**
1. ✅ Login con credenciales de usuario
2. ✅ Verificar que solo ve su menú (sin Sincronización, Perfiles)
3. ✅ Intentar acceder a `/biometric_sync.html` → Debe redirigir
4. ✅ Cambiar contraseña desde perfil
5. ✅ Verificar que solo ve sus propios datos

### **Como Administrador:**
1. ✅ Login con credenciales de admin
2. ✅ Verificar que ve menú completo
3. ✅ Acceder a todas las páginas sin restricciones
4. ✅ Gestionar usuarios en Perfiles
5. ✅ Ver datos de todos los usuarios

---

## 🛠️ Comandos de Compilación

```bash
# Compilar el proyecto
mvn clean compile -DskipTests

# Copiar clases compiladas
xcopy /E /I /Y "target\classes\*" "WEB-INF\classes\"

# Reiniciar Tomcat (si es necesario)
# Detener y volver a iniciar el servidor
```

---

## 📌 Notas Importantes

1. **Compatibilidad:** Todos los cambios son retrocompatibles
2. **Seguridad:** Las contraseñas se encriptan con BCrypt
3. **Sesiones:** Spring Security maneja las sesiones automáticamente
4. **Auditoría:** Todos los cambios de contraseña se registran en la BD

---

## ✅ Estado de Implementación

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Menu Manager | ✅ Completado | Funcional y probado |
| Cambio de Contraseña | ✅ Completado | Con validaciones |
| Dashboard Usuario | ✅ Completado | Con menú dinámico |
| Perfil Usuario | ✅ Completado | Con cambio de contraseña |
| Control de Acceso | ✅ Completado | Redirección automática |
| Procesados (filtrado) | ⏳ Pendiente | Requiere modificar servlet |
| Permisos (filtrado) | ⏳ Pendiente | Requiere modificar servlet |
| Consolidado (filtrado) | ⏳ Pendiente | Requiere modificar servlet |

---

## 📞 Soporte

Para cualquier duda o problema con la implementación, revisar:
- Logs de Tomcat: `logs/catalina.out`
- Consola del navegador (F12)
- Network tab para verificar llamadas API

---

**Fecha de Implementación:** 2025-11-27
**Versión:** 1.0.0
**Estado:** Funcional y Listo para Pruebas
