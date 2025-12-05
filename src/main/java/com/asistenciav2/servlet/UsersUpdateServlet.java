package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;

@WebServlet("/api/users/update")
public class UsersUpdateServlet extends HttpServlet {

    /**
     * Obtiene el ID del usuario autenticado actualmente.
     * 
     * @param conn Conexión a la base de datos
     * @return ID del usuario autenticado, o null si no está autenticado
     */
    private Integer getAuthenticatedUserId(Connection conn) {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication == null || !authentication.isAuthenticated() ||
                    "anonymousUser".equals(authentication.getPrincipal())) {
                return null;
            }

            String username = authentication.getName();

            // Buscar el ID del usuario en la base de datos usando email o dni
            String sql = "SELECT id FROM users WHERE (email = ? OR dni = ?) AND estado = 1 LIMIT 1";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, username);
                ps.setString(2, username);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt("id");
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error obteniendo ID de usuario autenticado: " + e.getMessage());
        }
        return null;
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String idStr = req.getParameter("id");
        String nombre = req.getParameter("nombre");
        String apellidos = req.getParameter("apellidos");
        String email = req.getParameter("email");
        String rolStr = req.getParameter("rol");
        String estadoStr = req.getParameter("estado");
        try (Connection conn = DatabaseConnection.getConnection()) {
            String role = ("ADMIN".equalsIgnoreCase(rolStr)) ? "administrador" : "usuario";
            int estado = (estadoStr != null && !estadoStr.isEmpty()) ? Integer.parseInt(estadoStr) : 1;

            // Obtener el ID del usuario administrador autenticado
            Integer adminUserId = getAuthenticatedUserId(conn);

            // Fallback: si no hay usuario autenticado en el contexto, buscar un admin en la
            // BD
            if (adminUserId == null) {
                try (PreparedStatement psAdmin = conn.prepareStatement(
                        "SELECT id FROM users WHERE role = 'administrador' AND estado = 1 ORDER BY id ASC LIMIT 1")) {
                    try (ResultSet rsAdmin = psAdmin.executeQuery()) {
                        if (rsAdmin.next()) {
                            adminUserId = rsAdmin.getInt("id");
                        }
                    }
                } catch (Exception e) {
                    System.err.println("Error buscando admin fallback: " + e.getMessage());
                }
            }

            String sql = "UPDATE users SET nombre=?, apellidos=?, email=?, role=?, estado=?, usermod=? WHERE id=?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setString(1, nombre);
                ps.setString(2, apellidos);
                ps.setString(3, email);
                ps.setString(4, role);
                ps.setInt(5, estado);

                // Si no se puede obtener el admin, usar NULL
                if (adminUserId != null) {
                    ps.setInt(6, adminUserId); // usermod
                } else {
                    ps.setNull(6, Types.INTEGER);
                }

                ps.setInt(7, Integer.parseInt(idStr));
                ps.executeUpdate();
            }
            resp.getWriter().write("{\"success\":true,\"message\":\"Usuario actualizado\"}");
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error actualizando usuario\"}");
        }
    }
}