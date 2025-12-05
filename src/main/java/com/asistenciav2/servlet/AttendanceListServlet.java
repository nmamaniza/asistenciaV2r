package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

@WebServlet("/api/attendances")
public class AttendanceListServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        // Verificar autenticación con Spring Security
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() ||
                "anonymousUser".equals(authentication.getPrincipal())) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("{\"error\":\"No autorizado\"}");
            return;
        }

        // Obtener el DNI del usuario logueado desde la base de datos usando el username
        String username = authentication.getName();
        String userDni = getUserDniFromDatabase(username);

        if (userDni == null) {
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            response.getWriter().write("{\"error\":\"DNI de usuario no encontrado\"}");
            return;
        }

        List<Map<String, Object>> attendanceList = new ArrayList<>();

        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT a.dni, a.nombre, a.fechahora, a.fecha, a.hora, a.reloj, a.tipo_marcaje, a.mensaje " +
                    "FROM attendances a " +
                    "WHERE a.dni = ? " +
                    "ORDER BY a.fechahora DESC " +
                    "LIMIT 1000";

            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, userDni);
                ResultSet rs = stmt.executeQuery();

                while (rs.next()) {
                    Map<String, Object> attendance = new HashMap<>();
                    attendance.put("dni", rs.getString("dni"));
                    attendance.put("nombre", rs.getString("nombre"));
                    attendance.put("fechahora", rs.getTimestamp("fechahora"));
                    attendance.put("fecha", rs.getDate("fecha"));
                    attendance.put("hora", rs.getTime("hora"));
                    attendance.put("reloj", rs.getString("reloj"));
                    attendance.put("tipo_marcaje", rs.getString("tipo_marcaje"));
                    attendance.put("mensaje", rs.getString("mensaje"));

                    attendanceList.add(attendance);
                }
            }

        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"error\":\"Error de base de datos\"}");
            return;
        }

        // Convertir a JSON
        ObjectMapper mapper = new ObjectMapper();
        String jsonResponse = mapper.writeValueAsString(attendanceList);

        PrintWriter out = response.getWriter();
        out.print(jsonResponse);
        out.flush();
    }

    private String getUserDniFromDatabase(String username) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT dni FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            try (PreparedStatement stmt = conn.prepareStatement(sql)) {
                stmt.setString(1, username);
                stmt.setString(2, username);
                ResultSet rs = stmt.executeQuery();

                if (rs.next()) {
                    return rs.getString("dni");
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }
}