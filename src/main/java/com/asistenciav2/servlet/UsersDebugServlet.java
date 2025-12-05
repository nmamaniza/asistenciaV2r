package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.sql.*;
import java.util.*;

@WebServlet("/api/users/debug")
public class UsersDebugServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");
        
        System.out.println("[UsersDebugServlet] Iniciando análisis detallado de usuarios...");
        
        Map<String, Object> debugInfo = new LinkedHashMap<>();
        List<Map<String, Object>> users = new ArrayList<>();
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            System.out.println("[UsersDebugServlet] Conexión establecida");
            
            // Primero, obtener estadísticas de la tabla
            String statsSQL = "SELECT COUNT(*) as total, " +
                            "COUNT(CASE WHEN estado = 1 THEN 1 END) as activos, " +
                            "COUNT(CASE WHEN estado = 0 THEN 1 END) as inactivos " +
                            "FROM users";
            
            try (PreparedStatement statsStmt = conn.prepareStatement(statsSQL)) {
                ResultSet statsRs = statsStmt.executeQuery();
                if (statsRs.next()) {
                    debugInfo.put("total_users", statsRs.getInt("total"));
                    debugInfo.put("active_users", statsRs.getInt("activos"));
                    debugInfo.put("inactive_users", statsRs.getInt("inactivos"));
                }
            }
            
            // Obtener estructura de la tabla
            DatabaseMetaData metaData = conn.getMetaData();
            ResultSet columns = metaData.getColumns(null, null, "users", null);
            
            List<Map<String, String>> tableStructure = new ArrayList<>();
            while (columns.next()) {
                Map<String, String> column = new LinkedHashMap<>();
                column.put("name", columns.getString("COLUMN_NAME"));
                column.put("type", columns.getString("TYPE_NAME"));
                column.put("size", String.valueOf(columns.getInt("COLUMN_SIZE")));
                column.put("nullable", String.valueOf(columns.getBoolean("NULLABLE")));
                tableStructure.add(column);
            }
            debugInfo.put("table_structure", tableStructure);
            
            // Obtener datos de usuarios con información detallada
            String q = req.getParameter("q");
            String estadoParam = req.getParameter("estado");
            String limitParam = req.getParameter("limit");
            int limit = limitParam != null ? Integer.parseInt(limitParam) : 50;
            
            StringBuilder sql = new StringBuilder("SELECT id, dni, nombre, apellidos, email, role, estado FROM users WHERE 1=1");
            List<Object> params = new ArrayList<>();
            
            if (estadoParam != null && ("0".equals(estadoParam) || "1".equals(estadoParam))) {
                sql.append(" AND estado = ?");
                params.add(Integer.parseInt(estadoParam));
            } else {
                sql.append(" AND estado IN (0,1)");
            }
            
            if (q != null && !q.isEmpty()) {
                sql.append(" AND (dni LIKE ? OR UPPER(nombre || ' ' || COALESCE(apellidos,'')) LIKE UPPER(?))");
                String pat = "%" + q + "%";
                params.add(pat); 
                params.add(pat);
            }
            
            sql.append(" ORDER BY nombre ASC");
            sql.append(" LIMIT ?");
            params.add(limit);
            
            System.out.println("[UsersDebugServlet] SQL: " + sql.toString());
            System.out.println("[UsersDebugServlet] Parámetros: " + params);
            
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }
                
                ResultSet rs = ps.executeQuery();
                int count = 0;
                
                while (rs.next() && count < limit) {
                    Map<String, Object> user = new LinkedHashMap<>();
                    
                    // Obtener cada campo con verificación de nulos
                    user.put("id", rs.getObject("id"));
                    user.put("dni", rs.getObject("dni"));
                    user.put("nombre", rs.getObject("nombre"));
                    user.put("apellidos", rs.getObject("apellidos"));
                    user.put("email", rs.getObject("email"));
                    
                    String role = rs.getString("role");
                    String rolOut = (role != null && role.equalsIgnoreCase("administrador")) ? "ADMIN" : "USER";
                    user.put("rol", rolOut);
                    
                    user.put("estado", rs.getObject("estado"));
                    
                    // Agregar información adicional de debug
                    Map<String, Object> debug = new LinkedHashMap<>();
                    debug.put("raw_role", role);
                    debug.put("row_number", ++count);
                    
                    // Verificar tipos de datos
                    ResultSetMetaData rsMetaData = rs.getMetaData();
                    for (int i = 1; i <= rsMetaData.getColumnCount(); i++) {
                        String columnName = rsMetaData.getColumnName(i);
                        Object value = rs.getObject(i);
                        if (value != null) {
                            debug.put(columnName + "_type", value.getClass().getSimpleName());
                        }
                    }
                    
                    user.put("_debug", debug);
                    users.add(user);
                }
                
                debugInfo.put("returned_count", users.size());
                debugInfo.put("sql_query", sql.toString());
                debugInfo.put("parameters", params);
                
            }
            
            debugInfo.put("users", users);
            debugInfo.put("timestamp", new java.util.Date().toInstant().toString());
            debugInfo.put("status", "success");
            
        } catch (SQLException e) {
            System.err.println("[UsersDebugServlet] Error de base de datos: " + e.getMessage());
            e.printStackTrace();
            
            debugInfo.put("status", "error");
            debugInfo.put("error_type", "database");
            debugInfo.put("error_message", e.getMessage());
            debugInfo.put("sql_state", e.getSQLState());
            debugInfo.put("error_code", e.getErrorCode());
            
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        } catch (Exception e) {
            System.err.println("[UsersDebugServlet] Error inesperado: " + e.getMessage());
            e.printStackTrace();
            
            debugInfo.put("status", "error");
            debugInfo.put("error_type", "unexpected");
            debugInfo.put("error_message", e.getMessage());
            debugInfo.put("error_class", e.getClass().getSimpleName());
            
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
        }
        
        // Enviar respuesta
        ObjectMapper mapper = new ObjectMapper();
        String jsonResponse = mapper.writeValueAsString(debugInfo);
        
        System.out.println("[UsersDebugServlet] Respuesta enviada: " + jsonResponse.substring(0, Math.min(500, jsonResponse.length())) + "...");
        resp.getWriter().write(jsonResponse);
    }
}