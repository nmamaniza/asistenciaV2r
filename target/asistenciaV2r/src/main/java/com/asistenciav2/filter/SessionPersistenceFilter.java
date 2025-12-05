package com.asistenciav2.filter;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

public class SessionPersistenceFilter implements Filter {

    @Override
    public void init(FilterConfig filterConfig) throws ServletException {
        // Inicialización del filtro
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        
        HttpServletRequest httpRequest = (HttpServletRequest) request;
        HttpServletResponse httpResponse = (HttpServletResponse) response;
        
        HttpSession session = httpRequest.getSession(false);
        
        // Si la sesión existe, renovamos su tiempo de vida
        if (session != null) {
            // Renovar la sesión
            session.setMaxInactiveInterval(-1); // Nunca expira
        }
        
        chain.doFilter(request, response);
    }

    @Override
    public void destroy() {
        // Limpieza de recursos
    }
}