package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.*;
import jakarta.servlet.annotation.WebServlet;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@WebServlet("/api/processed-data")
public class ProcessedDataServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        String mesStr = req.getParameter("mes");
        String anioStr = req.getParameter("anio");
        String dniOrNombre = req.getParameter("q");
        List<Map<String, Object>> out = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder();
            sql.append("SELECT da.id, u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("da.fecha, da.obs, da.doc, da.final, da.horaint, ja.cargo, ja.area, ja.modalidad ");
            sql.append("FROM dailyattendances da ");
            sql.append("JOIN jobassignments ja ON ja.id = da.jobassignment_id ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("WHERE da.estado = 1 ");
            List<Object> params = new ArrayList<>();
            if (anioStr != null && !anioStr.isEmpty()) {
                sql.append("AND EXTRACT(YEAR FROM da.fecha) = ? ");
                params.add(Integer.parseInt(anioStr));
            }
            if (mesStr != null && !mesStr.isEmpty()) {
                sql.append("AND EXTRACT(MONTH FROM da.fecha) = ? ");
                params.add(Integer.parseInt(mesStr));
            }
            if (dniOrNombre != null && !dniOrNombre.isEmpty()) {
                sql.append("AND (u.dni LIKE ? OR UPPER(u.nombre || ' ' || COALESCE(u.apellidos,'')) LIKE UPPER(?)) ");
                String pat = "%" + dniOrNombre + "%";
                params.add(pat);
                params.add(pat);
            }
            sql.append("ORDER BY da.fecha DESC, u.dni ASC, ja.cargo ASC LIMIT 2000");
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("dni", rs.getString("dni"));
                    row.put("nombre", rs.getString("nombre"));
                    row.put("fecha", rs.getDate("fecha"));
                    row.put("obs", rs.getString("obs"));
                    row.put("doc", rs.getString("doc"));
                    row.put("final", rs.getString("final"));
                    row.put("horaint", rs.getString("horaint"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("area", rs.getString("area"));
                    row.put("modalidad", rs.getString("modalidad"));
                    out.add(row);
                }
            }
        } catch (SQLException e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }
}