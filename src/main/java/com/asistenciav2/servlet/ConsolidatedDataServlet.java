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
import java.sql.SQLException;
import java.util.*;

@WebServlet("/api/consolidated-data")
public class ConsolidatedDataServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        String anioStr = req.getParameter("anio");
        String mesStr = req.getParameter("mes");
        String q = req.getParameter("q");
        Integer anio, mes;
        try {
            anio = (anioStr != null && !anioStr.isEmpty()) ? Integer.parseInt(anioStr) : null;
            mes = (mesStr != null && !mesStr.isEmpty()) ? Integer.parseInt(mesStr) : null;
        } catch (NumberFormatException e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"Parámetros de año/mes inválidos\"}");
            return;
        }
        if (anio == null || mes == null) {
            java.time.LocalDate now = java.time.LocalDate.now();
            anio = now.getYear();
            mes = now.getMonthValue();
        }

        Map<String, Map<String, Object>> rows = new LinkedHashMap<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder();
            sql.append("SELECT u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("ja.modalidad, ja.cargo, ja.area, ja.id as job_id, da.fecha, da.final ");
            sql.append("FROM jobassignments ja ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("LEFT JOIN dailyattendances da ON da.jobassignment_id = ja.id ");
            sql.append("AND EXTRACT(YEAR FROM da.fecha) = ? AND EXTRACT(MONTH FROM da.fecha) = ? AND da.estado = 1 ");
            sql.append("WHERE ja.estado = 1 ");
            List<Object> params = new ArrayList<>();
            params.add(anio);
            params.add(mes);
            if (q != null && !q.isEmpty()) {
                sql.append("AND (u.dni LIKE ? OR UPPER(u.nombre || ' ' || COALESCE(u.apellidos,'')) LIKE UPPER(?)) ");
                String pat = "%" + q + "%";
                params.add(pat);
                params.add(pat);
            }
            sql.append("ORDER BY u.dni ASC, ja.id ASC, da.fecha ASC");
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }
                ResultSet rs = ps.executeQuery();
                final int anioVal = anio;
                final int mesVal = mes;
                final int daysInMonth = java.time.YearMonth.of(anioVal, mesVal).lengthOfMonth();
                while (rs.next()) {
                    String dni = rs.getString("dni");
                    String nombre = rs.getString("nombre");
                    String modalidad = rs.getString("modalidad");
                    String cargo = rs.getString("cargo");
                    String area = rs.getString("area");
                    long jobId = rs.getLong("job_id");

                    // Use a composite key or unique job ID to distinguish rows
                    String rowKey = dni + "_" + jobId;

                    Map<String, Object> row = rows.computeIfAbsent(rowKey, k -> {
                        Map<String, Object> m = new LinkedHashMap<>();
                        m.put("dni", dni);
                        m.put("nombre", nombre);
                        m.put("modalidad", modalidad);
                        m.put("cargo", cargo != null ? cargo : "");
                        m.put("area", area != null ? area : "");
                        for (int d = 1; d <= daysInMonth; d++) {
                            m.put("d" + String.format("%02d", d), "");
                        }
                        return m;
                    });
                    java.sql.Date f = rs.getDate("fecha");
                    if (f != null) {
                        java.time.LocalDate ld = f.toLocalDate();
                        int day = ld.getDayOfMonth();
                        String key = "d" + String.format("%02d", day);
                        row.put(key, rs.getString("final"));
                    }
                }
            }
        } catch (SQLException e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error de servidor\"}");
            return;
        }
        List<Map<String, Object>> out = new ArrayList<>(rows.values());
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }
}