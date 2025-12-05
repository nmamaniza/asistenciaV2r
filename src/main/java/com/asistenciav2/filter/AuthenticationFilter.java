package com.asistenciav2.filter;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;

public class AuthenticationFilter implements Filter {
    
    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        
        HttpServletRequest httpRequest = (HttpServletRequest) request;
        HttpServletResponse httpResponse = (HttpServletResponse) response;
        
        String requestURI = httpRequest.getRequestURI();
        String contextPath = httpRequest.getContextPath();
        
        // Rutas que no requieren autenticación
        if (requestURI.endsWith("/login.html") || 
            requestURI.endsWith("/login") ||
            requestURI.contains("/css/") ||
            requestURI.contains("/js/") ||
            requestURI.contains("/resources/")) {
            chain.doFilter(request, response);
            return;
        }
        
        HttpSession session = httpRequest.getSession(false);
        boolean isLoggedIn = (session != null && session.getAttribute("user") != null);
        
        // Si está logueado y trata de acceder a login, redirigir a dashboard
        if (isLoggedIn && requestURI.endsWith("/login.html")) {
            httpResponse.sendRedirect("/asistenciaV2r/dashboard.html");
            return;
        }
        
        // Si no está logueado y trata de acceder a páginas protegidas
        if (!isLoggedIn && !requestURI.endsWith("/login.html")) {
            httpResponse.sendRedirect("/asistenciaV2r/login.html");
            return;
        }
        
        chain.doFilter(request, response);
    }
}