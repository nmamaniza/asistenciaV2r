package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.asistenciav2.util.BCryptUtil;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;

public class LoginServlet extends HttpServlet {
    
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        String identifier = request.getParameter("identifier"); // DNI o email
        String password = request.getParameter("password");
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id, nombre, apellidos, email, dni, password, role FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            PreparedStatement stmt = conn.prepareStatement(sql);
            stmt.setString(1, identifier);
            stmt.setString(2, identifier);
            
            ResultSet rs = stmt.executeQuery();
            
            if (rs.next()) {
                String storedHash = rs.getString("password");
                
                if (BCryptUtil.checkPassword(password, storedHash)) {
                    // Login exitoso
                    HttpSession session = request.getSession(true);
                    session.setAttribute("user", rs.getString("nombre"));
                    session.setAttribute("userId", rs.getInt("id"));
                    session.setAttribute("email", rs.getString("email"));
                    session.setAttribute("dni", rs.getString("dni"));
                    session.setAttribute("apellidos", rs.getString("apellidos"));
                    session.setAttribute("role", rs.getString("role"));
                    
                    // Configurar sesión para que nunca caduque
                    session.setMaxInactiveInterval(-1);
                    
                    // Actualizar último acceso
                    updateLastAccess(conn, rs.getInt("id"));
                    
                    // Redirigir según el rol
                    String role = rs.getString("role");
                    if ("administrador".equals(role)) {
                        response.sendRedirect("/asistenciaV2r/dashboard_admin.html");
                    } else {
                        response.sendRedirect("/asistenciaV2r/dashboard.html");
                    }
                } else {
                    // Contraseña incorrecta
                    response.sendRedirect("/asistenciaV2r/login.html?error=invalid");
                }
            } else {
                // Usuario no encontrado o inactivo
                response.sendRedirect("/asistenciaV2r/login.html?error=notfound");
            }
            
        } catch (SQLException e) {
            e.printStackTrace();
            response.sendRedirect("/asistenciaV2r/login.html?error=database");
        }
    }
    
    private void updateLastAccess(Connection conn, int userId) {
        try {
            String updateSql = "UPDATE users SET ultimo_acceso = ? WHERE id = ?";
            PreparedStatement updateStmt = conn.prepareStatement(updateSql);
            updateStmt.setTimestamp(1, new Timestamp(System.currentTimeMillis()));
            updateStmt.setInt(2, userId);
            updateStmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }
}