package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
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
import java.sql.Timestamp;
import java.sql.Time;
import java.time.format.DateTimeFormatter;

public class SearchAttendanceServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type");
        
        // Verificar autenticación con Spring Security (como AttendanceListServlet)
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || 
            "anonymousUser".equals(authentication.getPrincipal())) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("{\"error\":\"No autorizado\",\"success\":false}");
            return;
        }
        
        String startDate = request.getParameter("startDate");
        String endDate = request.getParameter("endDate");
        String userSearch = request.getParameter("user");
        
        List<Map<String, Object>> attendanceList = new ArrayList<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder();
            sql.append("SELECT DISTINCT a.dni, a.nombre, a.fechahora, a.fecha, a.hora, ");
            sql.append("COALESCE(a.reloj, '') as reloj, ");
            sql.append("a.tipo_marcaje as tipo_marcaje, ");
            sql.append("COALESCE(a.mensaje, '') as mensaje, ");
            sql.append("a.user_id ");
            sql.append("FROM attendances a ");
            sql.append("WHERE estado=1 ");
            
            List<Object> parameters = new ArrayList<>();
            
            // Filtro por fechas (inclusivo); si inicio==fin, igualdad exacta
            java.sql.Date startSqlDate = null;
            java.sql.Date endSqlDate = null;
            if (startDate != null && !startDate.trim().isEmpty()) {
                try {
                    startSqlDate = java.sql.Date.valueOf(startDate.trim());
                } catch (IllegalArgumentException e) {
                    response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                    response.getWriter().write("{\"success\":false,\"message\":\"Fecha de inicio inválida\"}");
                    return;
                }
            }
            if (endDate != null && !endDate.trim().isEmpty()) {
                try {
                    endSqlDate = java.sql.Date.valueOf(endDate.trim());
                } catch (IllegalArgumentException e) {
                    response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                    response.getWriter().write("{\"success\":false,\"message\":\"Fecha de fin inválida\"}");
                    return;
                }
            }
            if (startSqlDate != null && endSqlDate != null) {
                if (startSqlDate.equals(endSqlDate)) {
                    sql.append("AND a.fecha = ? ");
                    parameters.add(startSqlDate);
                } else {
                    sql.append("AND a.fecha >= ? AND a.fecha <= ? ");
                    parameters.add(startSqlDate);
                    parameters.add(endSqlDate);
                }
            } else if (startSqlDate != null) {
                sql.append("AND a.fecha >= ? ");
                parameters.add(startSqlDate);
            } else if (endSqlDate != null) {
                sql.append("AND a.fecha <= ? ");
                parameters.add(endSqlDate);
            }
            
            // Filtro por usuario (DNI o nombre)
            if (userSearch != null && !userSearch.trim().isEmpty()) {
                sql.append("AND (a.dni LIKE ? OR UPPER(a.nombre) LIKE UPPER(?)) ");
                String searchPattern = "%" + userSearch.trim() + "%";
                parameters.add(searchPattern);
                parameters.add(searchPattern);
            }
            
            sql.append("ORDER BY a.fechahora DESC LIMIT 1000");
            
            try (PreparedStatement stmt = conn.prepareStatement(sql.toString())) {
                // Establecer parámetros con tipos adecuados
                for (int i = 0; i < parameters.size(); i++) {
                    Object p = parameters.get(i);
                    if (p instanceof java.sql.Date) {
                        stmt.setDate(i + 1, (java.sql.Date) p);
                    } else {
                        stmt.setObject(i + 1, p);
                    }
                }
                
                ResultSet rs = stmt.executeQuery();
                
                while (rs.next()) {
                    Map<String, Object> attendance = new HashMap<>();
                    attendance.put("dni", rs.getString("dni"));
                    attendance.put("nombre", rs.getString("nombre"));
                    // Enviar fechahora como epoch ms para evitar desfases por zona horaria
                    Timestamp ts = rs.getTimestamp("fechahora");
                    attendance.put("fechahora", ts != null ? ts.getTime() : null);
                    // Enviar fecha como string yyyy-MM-dd para representación exacta del día
                    java.sql.Date sqlDate = rs.getDate("fecha");
                    String fechaStr = (sqlDate != null) ? sqlDate.toLocalDate().format(DateTimeFormatter.ISO_LOCAL_DATE) : null;
                    attendance.put("fecha", fechaStr);
                    // Enviar hora como string HH:mm:ss (formato por defecto de Time)
                    Time time = rs.getTime("hora");
                    attendance.put("hora", time != null ? time.toString() : null);
                    attendance.put("reloj", rs.getString("reloj"));
                    attendance.put("tipo_marcaje", rs.getString("tipo_marcaje"));
                    attendance.put("mensaje", rs.getString("mensaje"));
                    attendance.put("user_id", rs.getObject("user_id"));
                    
                    attendanceList.add(attendance);
                }
            }
            
        } catch (SQLException e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\":false,\"message\":\"Error de base de datos\"}");
            return;
        } catch (Exception e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\":false,\"message\":\"Error interno del servidor\"}");
            return;
        }
        
        // Convertir a JSON - retornar array directo
        ObjectMapper mapper = new ObjectMapper();
        String jsonResponse = mapper.writeValueAsString(attendanceList);
        
        PrintWriter out = response.getWriter();
        out.print(jsonResponse);
        out.flush();
    }
    
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        doGet(request, response);
    }
}