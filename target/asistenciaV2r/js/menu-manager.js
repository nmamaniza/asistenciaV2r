/**
 * Menu Manager - Gestiona los menús según el rol del usuario
 */

// Configuración de menús por rol
const MENU_CONFIG = {
    ADMIN: [
        { icon: '🏠', text: 'Dashboard Admin', href: '/asistenciaV2r/dashboard_admin.html' },
        { icon: '🔄', text: 'Sincronización', href: '/asistenciaV2r/biometric_sync.html' },
        { icon: '📋', text: 'Procesados', href: '/asistenciaV2r/procesados.html' },
        { icon: '🔐', text: 'Permisos', href: '/asistenciaV2r/permisos.html' },
        { icon: '📊', text: 'Consolidado', href: '/asistenciaV2r/consolidado.html' },
        { icon: '👥', text: 'Perfiles', href: '/asistenciaV2r/perfiles.html' }
    ],
    USER: [
        { icon: '🏠', text: 'Dashboard', href: '/asistenciaV2r/dashboard.html' },
        { icon: '📋', text: 'Procesados', href: '/asistenciaV2r/procesados_user.html' },
        { icon: '🔐', text: 'Mis Permisos', href: '/asistenciaV2r/permiso_user.html' },
        { icon: '📊', text: 'Consolidado', href: '/asistenciaV2r/consolidado_user.html' },
        { icon: '👤', text: 'Mi Perfil', href: '/asistenciaV2r/perfil.html' }
    ]
};

// Páginas que requieren rol de administrador
const ADMIN_ONLY_PAGES = [
    'biometric_sync.html',
    'perfiles.html',
    'dashboard_admin.html'
];

class MenuManager {
    constructor() {
        this.userInfo = null;
        this.isAdmin = false;
    }

    /**
     * Inicializa el gestor de menús
     */
    async init() {
        try {
            await this.loadUserInfo();
            this.checkPageAccess();
            this.renderMenu();
            this.updateUserAvatar();
        } catch (error) {
            console.error('Error al inicializar MenuManager:', error);
            // Si hay error, redirigir al login
            if (window.location.pathname !== '/asistenciaV2r/login.html') {
                window.location.href = '/asistenciaV2r/login.html';
            }
        }
    }

    /**
     * Carga la información del usuario desde el servidor
     */
    async loadUserInfo() {
        try {
            const response = await fetch('/asistenciaV2r/api/userInfo', {
                credentials: 'include'
            });

            if (!response.ok) {
                throw new Error('No se pudo cargar la información del usuario');
            }

            const data = await response.json();

            if (data.success) {
                this.userInfo = data;
                this.isAdmin = data.isAdmin || false;
                return data;
            } else {
                throw new Error('Respuesta inválida del servidor');
            }
        } catch (error) {
            console.error('Error al cargar información del usuario:', error);
            throw error;
        }
    }

    /**
     * Verifica si el usuario tiene acceso a la página actual
     */
    checkPageAccess() {
        const currentPage = window.location.pathname.split('/').pop();

        // Si es una página solo para admin y el usuario no es admin, redirigir
        if (ADMIN_ONLY_PAGES.includes(currentPage) && !this.isAdmin) {
            console.warn('Acceso denegado: Esta página requiere privilegios de administrador');
            window.location.href = '/asistenciaV2r/dashboard.html';
            return false;
        }

        return true;
    }

    /**
     * Renderiza el menú según el rol del usuario
     */
    renderMenu() {
        const dropdownMenu = document.getElementById('dropdownMenu');
        if (!dropdownMenu) {
            console.warn('No se encontró el elemento dropdownMenu');
            return;
        }

        // Limpiar menú existente
        dropdownMenu.innerHTML = '';

        // Agregar header
        const header = document.createElement('div');
        header.className = 'dropdown-header';
        header.id = 'dropdownHeader';
        const fullName = [this.userInfo?.nombre, this.userInfo?.apellidos].filter(Boolean).join(' ').trim();
        header.textContent = fullName || this.userInfo?.nombre || (this.isAdmin ? 'Administrador' : 'Usuario');
        dropdownMenu.appendChild(header);

        // Obtener menú según rol
        const menuItems = this.isAdmin ? MENU_CONFIG.ADMIN : MENU_CONFIG.USER;

        // Agregar items del menú
        menuItems.forEach(item => {
            const link = document.createElement('a');
            link.href = item.href;
            link.className = 'dropdown-item';
            link.textContent = `${item.icon} ${item.text}`;
            link.style.display = 'block';
            link.style.textDecoration = 'none';
            dropdownMenu.appendChild(link);
        });

        // Agregar separador y logout
        const logoutLink = document.createElement('a');
        logoutLink.href = '/asistenciaV2r/logout';
        logoutLink.className = 'dropdown-item logout';
        logoutLink.textContent = '🚪 Cerrar Sesión';
        logoutLink.style.display = 'block';
        logoutLink.style.textDecoration = 'none';
        dropdownMenu.appendChild(logoutLink);
    }

    /**
     * Actualiza el avatar del usuario
     */
    updateUserAvatar() {
        const userAvatar = document.getElementById('userAvatar');
        const profileAvatar = document.getElementById('profileAvatar');

        if (this.userInfo) {
            const fullName = [this.userInfo.nombre, this.userInfo.apellidos].filter(Boolean).join(' ').trim();
            const baseName = fullName || this.userInfo.nombre || '';
            const initial = baseName ? baseName.charAt(0).toUpperCase() : 'U';

            if (userAvatar) {
                userAvatar.textContent = initial;
            }

            if (profileAvatar) {
                profileAvatar.textContent = initial;
            }
        }
    }

    /**
     * Obtiene el rol del usuario
     */
    getUserRole() {
        return this.isAdmin ? 'ADMIN' : 'USER';
    }

    /**
     * Verifica si el usuario es administrador
     */
    isUserAdmin() {
        return this.isAdmin;
    }

    /**
     * Obtiene la información del usuario
     */
    getUserInfo() {
        return this.userInfo;
    }
}

// Función global para toggle del dropdown
function toggleDropdown() {
    const dropdown = document.getElementById('dropdownMenu');
    if (dropdown) {
        dropdown.classList.toggle('show');
    }
}

// Cerrar el menú si se hace clic fuera de él
window.onclick = function (event) {
    if (!event.target.matches('.user-avatar')) {
        const dropdowns = document.getElementsByClassName('dropdown-menu');
        for (let i = 0; i < dropdowns.length; i++) {
            const openDropdown = dropdowns[i];
            if (openDropdown.classList.contains('show')) {
                openDropdown.classList.remove('show');
            }
        }
    }
}

// Exportar instancia global
window.menuManager = new MenuManager();
