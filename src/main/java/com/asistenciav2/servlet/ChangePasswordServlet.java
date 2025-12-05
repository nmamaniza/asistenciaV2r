package com.asistenciav2.servlet;

import com.asistenciav2.util.BCryptUtil;
import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

@WebServlet("/api/changePassword")
public class ChangePasswordServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        // Verificar autenticación
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() ||
                "anonymousUser".equals(authentication.getPrincipal())) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            writeJson(response, "{\"success\":false,\"message\":\"No autorizado\"}");
            return;
        }

        String username = authentication.getName();

        // Leer parámetros
        String currentPassword = request.getParameter("currentPassword");
        String newPassword = request.getParameter("newPassword");

        // Validar parámetros
        if (currentPassword == null || currentPassword.trim().isEmpty() ||
                newPassword == null || newPassword.trim().isEmpty()) {
            writeJson(response, "{\"success\":false,\"message\":\"Todos los campos son requeridos\"}");
            return;
        }

        // Validar longitud mínima de la nueva contraseña
        if (newPassword.length() < 6) {
            writeJson(response,
                    "{\"success\":false,\"message\":\"La nueva contraseña debe tener al menos 6 caracteres\"}");
            return;
        }

        try (Connection conn = DatabaseConnection.getConnection()) {
            // Obtener la contraseña actual del usuario
            String sql = "SELECT id, password FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            Integer userId = null;
            String storedPassword = null;

            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, username);
                stmt.setString(2, username);
                try (ResultSet rs = stmt.executeQuery()) {
                    if (rs.next()) {
                        userId = rs.getInt("id");
                        storedPassword = rs.getString("password");
                    } else {
                        writeJson(response, "{\"success\":false,\"message\":\"Usuario no encontrado\"}");
                        return;
                    }
                }
            }

            // Verificar la contraseña actual
            if (!BCryptUtil.checkPassword(currentPassword, storedPassword)) {
                writeJson(response, "{\"success\":false,\"message\":\"La contraseña actual es incorrecta\"}");
                return;
            }

            // Hashear la nueva contraseña
            String hashedNewPassword = BCryptUtil.hashPassword(newPassword);

            // Actualizar la contraseña
            String updateSql = "UPDATE users SET password = ?, usermod = ?, fechamod = NOW() WHERE id = ?";
            try (PreparedStatement updateStmt = conn.prepareStatement(updateSql)) {
                updateStmt.setString(1, hashedNewPassword);
                updateStmt.setInt(2, userId); // El usuario se modifica a sí mismo
                updateStmt.setInt(3, userId);

                int rowsAffected = updateStmt.executeUpdate();
                if (rowsAffected > 0) {
                    writeJson(response, "{\"success\":true,\"message\":\"Contraseña actualizada correctamente\"}");
                } else {
                    writeJson(response, "{\"success\":false,\"message\":\"No se pudo actualizar la contraseña\"}");
                }
            }

        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            writeJson(response,
                    "{\"success\":false,\"message\":\"Error de base de datos: " + escapeJson(e.getMessage()) + "\"}");
        }
    }

    private void writeJson(HttpServletResponse response, String json) throws IOException {
        PrintWriter out = response.getWriter();
        out.print(json);
        out.flush();
    }

    private String escapeJson(String text) {
        if (text == null)
            return "";
        return text.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r");
    }
}
