package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.*;

@WebServlet("/api/workschedules")
public class WorkschedulesServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id, descripcion, horaini, horafin, estado FROM workschedules WHERE estado = 1 ORDER BY id";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("descripcion", rs.getString("descripcion"));
                    row.put("horaini", String.valueOf(rs.getTime("horaini")));
                    row.put("horafin", String.valueOf(rs.getTime("horafin")));
                    out.add(row);
                }
            }
        } catch (Exception e) {}
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }
    
    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        
        String action = req.getParameter("action");
        
        if ("create".equals(action)) {
            handleCreate(req, resp);
        } else {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"Acción no válida\"}");
        }
    }
    
    private void handleCreate(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String descripcion = req.getParameter("descripcion");
        String horaini = req.getParameter("horaini");
        String horafin = req.getParameter("horafin");
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            if (descripcion == null || descripcion.isEmpty()) {
                throw new IllegalArgumentException("La descripción es requerida");
            }
            if (horaini == null || horaini.isEmpty()) {
                throw new IllegalArgumentException("La hora de inicio es requerida");
            }
            if (horafin == null || horafin.isEmpty()) {
                throw new IllegalArgumentException("La hora de fin es requerida");
            }
            
            String sql = "INSERT INTO workschedules (descripcion, horaini, horafin, estado) VALUES (?, ?, ?, 1)";
            try (PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setString(1, descripcion);
                ps.setString(2, horaini);
                ps.setString(3, horafin);
                
                int rows = ps.executeUpdate();
                if (rows == 0) {
                    throw new IllegalArgumentException("No se pudo crear el horario");
                }
                
                // Obtener el ID generado
                try (ResultSet generatedKeys = ps.getGeneratedKeys()) {
                    if (generatedKeys.next()) {
                        int newId = generatedKeys.getInt(1);
                        resp.getWriter().write("{\"success\":true,\"message\":\"Horario creado exitosamente\",\"id\":" + newId + "}");
                    } else {
                        resp.getWriter().write("{\"success\":true,\"message\":\"Horario creado exitosamente\"}");
                    }
                }
            }
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            String msg = e.getMessage();
            resp.getWriter().write("{\"success\":false,\"message\":\"" + (msg != null ? msg.replace("\"", "\\\"") : "Error creando horario") + "\"}");
        }
    }
}