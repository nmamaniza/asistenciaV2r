package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.*;
import jakarta.servlet.annotation.WebServlet;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@WebServlet("/api/check-tables")
public class CheckTableStructureServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        
        Map<String, Object> result = new HashMap<>();
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            // Verificar estructura de jobassignments
            DatabaseMetaData meta = conn.getMetaData();
            ResultSet columns = meta.getColumns(null, null, "jobassignments", null);
            
            List<Map<String, String>> jobassignmentColumns = new ArrayList<>();
            while (columns.next()) {
                Map<String, String> col = new HashMap<>();
                col.put("column_name", columns.getString("COLUMN_NAME"));
                col.put("data_type", columns.getString("TYPE_NAME"));
                jobassignmentColumns.add(col);
            }
            result.put("jobassignments_columns", jobassignmentColumns);
            
            // Verificar algunos datos de ejemplo
            String sql = "SELECT id, cargo, area, modalidad FROM jobassignments LIMIT 5";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ResultSet rs = ps.executeQuery();
                List<Map<String, Object>> sampleData = new ArrayList<>();
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("id", rs.getInt("id"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("area", rs.getString("area"));
                    row.put("modalidad", rs.getString("modalidad"));
                    sampleData.add(row);
                }
                result.put("jobassignments_sample", sampleData);
            }
            
            // Verificar datos con join
            String joinSql = "SELECT ja.id, ja.cargo, ja.area, ja.modalidad, u.dni, u.nombre " +
                           "FROM jobassignments ja " +
                           "JOIN users u ON u.id = ja.user_id " +
                           "LIMIT 5";
            try (PreparedStatement ps = conn.prepareStatement(joinSql)) {
                ResultSet rs = ps.executeQuery();
                List<Map<String, Object>> joinData = new ArrayList<>();
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("jobassignment_id", rs.getInt("id"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("area", rs.getString("area"));
                    row.put("modalidad", rs.getString("modalidad"));
                    row.put("user_dni", rs.getString("dni"));
                    row.put("user_nombre", rs.getString("nombre"));
                    joinData.add(row);
                }
                result.put("join_sample", joinData);
            }
            
        } catch (SQLException e) {
            result.put("error", e.getMessage());
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
        
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(result));
    }
}