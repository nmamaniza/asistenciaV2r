package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.*;

@WebServlet("/api/consolidated-data-user")
public class ConsolidatedDataUserServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json");
        resp.setCharacterEncoding("UTF-8");

        Integer userId = getAuthenticatedUserId();
        if (userId == null) {
            resp.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            resp.getWriter().write("{\"success\":false,\"message\":\"No autorizado\"}");
            return;
        }

        // Get date range parameters
        String anioInicioStr = req.getParameter("anioInicio");
        String mesInicioStr = req.getParameter("mesInicio");
        String anioFinStr = req.getParameter("anioFin");
        String mesFinStr = req.getParameter("mesFin");

        // Fallback to old single month parameters for backward compatibility
        if (anioInicioStr == null || mesInicioStr == null) {
            anioInicioStr = req.getParameter("anio");
            mesInicioStr = req.getParameter("mes");
            anioFinStr = anioInicioStr;
            mesFinStr = mesInicioStr;
        }

        Integer anioInicio, mesInicio, anioFin, mesFin;
        try {
            anioInicio = (anioInicioStr != null && !anioInicioStr.isEmpty()) ? Integer.parseInt(anioInicioStr) : null;
            mesInicio = (mesInicioStr != null && !mesInicioStr.isEmpty()) ? Integer.parseInt(mesInicioStr) : null;
            anioFin = (anioFinStr != null && !anioFinStr.isEmpty()) ? Integer.parseInt(anioFinStr) : null;
            mesFin = (mesFinStr != null && !mesFinStr.isEmpty()) ? Integer.parseInt(mesFinStr) : null;
        } catch (NumberFormatException e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("{\"success\":false,\"message\":\"Parámetros de fecha inválidos\"}");
            return;
        }

        // Default to current month if no parameters provided
        if (anioInicio == null || mesInicio == null) {
            LocalDate now = LocalDate.now();
            anioInicio = now.getYear();
            mesInicio = now.getMonthValue();
            anioFin = anioInicio;
            mesFin = mesInicio;
        }

        // If only start date provided, use it for end date too
        if (anioFin == null || mesFin == null) {
            anioFin = anioInicio;
            mesFin = mesInicio;
        }

        LocalDate startDate = LocalDate.of(anioInicio, mesInicio, 1);
        LocalDate endDate = LocalDate.of(anioFin, mesFin, 1).plusMonths(1).minusDays(1);

        Map<String, Map<String, Object>> rows = new LinkedHashMap<>();
        try (Connection conn = DatabaseConnection.getConnection()) {
            StringBuilder sql = new StringBuilder();
            sql.append("SELECT u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("ja.id AS job_id, ja.modalidad, ja.cargo, ja.fechaini AS job_ini, ja.fechafin AS job_fin, ");
            sql.append("da.fecha, da.final ");
            sql.append("FROM jobassignments ja ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("LEFT JOIN dailyattendances da ON da.jobassignment_id = ja.id ");
            sql.append("AND da.estado = 1 AND da.fecha >= ? AND da.fecha <= ? ");
            sql.append("WHERE u.id = ? AND ja.estado = 1 ");
            sql.append("ORDER BY ja.id, da.fecha ASC");

            System.out.println("=== ConsolidatedDataUserServlet DEBUG ===");
            System.out.println("Query: " + sql.toString());
            System.out.println("UserId: " + userId);
            System.out.println("StartDate: " + startDate);
            System.out.println("EndDate: " + endDate);

            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                ps.setDate(1, java.sql.Date.valueOf(startDate));
                ps.setDate(2, java.sql.Date.valueOf(endDate));
                ps.setInt(3, userId);

                ResultSet rs = ps.executeQuery();
                int rowCount = 0;

                while (rs.next()) {
                    rowCount++;
                    String dni = rs.getString("dni");
                    String nombre = rs.getString("nombre");
                    int jobId = rs.getInt("job_id");
                    String modalidad = rs.getString("modalidad");
                    String cargo = rs.getString("cargo");
                    java.sql.Date jobIni = rs.getDate("job_ini");
                    java.sql.Date jobFin = rs.getDate("job_fin");
                    java.sql.Date fecha = rs.getDate("fecha");
                    String finalValue = rs.getString("final");

                    System.out.println("Row " + rowCount + ": dni=" + dni + ", jobId=" + jobId + ", fecha=" + fecha
                            + ", final=" + finalValue);

                    // Group by DNI + JobID to support multiple roles
                    String rowKey = dni + "_" + jobId;

                    Map<String, Object> row = rows.computeIfAbsent(rowKey, k -> {
                        Map<String, Object> m = new LinkedHashMap<>();
                        m.put("dni", dni);
                        m.put("nombre", nombre);
                        m.put("job_id", jobId);
                        m.put("modalidad", modalidad);
                        m.put("cargo", cargo);
                        m.put("job_ini", jobIni != null ? jobIni.toString() : "");
                        m.put("job_fin", jobFin != null ? jobFin.toString() : "");

                        // Initialize all days in the date range
                        LocalDate current = startDate;
                        while (!current.isAfter(endDate)) {
                            String key = "d_" + current.getYear() +
                                    String.format("%02d", current.getMonthValue()) +
                                    String.format("%02d", current.getDayOfMonth());
                            m.put(key, "");
                            current = current.plusDays(1);
                        }
                        return m;
                    });

                    if (fecha != null) {
                        LocalDate ld = fecha.toLocalDate();
                        String key = "d_" + ld.getYear() +
                                String.format("%02d", ld.getMonthValue()) +
                                String.format("%02d", ld.getDayOfMonth());
                        row.put(key, finalValue);
                        System.out.println("Setting key: " + key + " = " + finalValue);
                    }
                }

                System.out.println("Total rows found: " + rowCount);
                System.out.println("Rows map size: " + rows.size());
            }
        } catch (SQLException e) {
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error de servidor\"}");
            return;
        }

        List<Map<String, Object>> out = new ArrayList<>(rows.values());
        System.out.println("Returning " + out.size() + " records");
        System.out.println("=========================================");

        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }

    private Integer getAuthenticatedUserId() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication == null || !authentication.isAuthenticated()) {
                return null;
            }
            String username = authentication.getName();
            if (username == null || username.equals("anonymousUser")) {
                return null;
            }

            try (Connection conn = DatabaseConnection.getConnection()) {
                String sql = "SELECT id, dni FROM users WHERE (email = ? OR dni = ?) AND estado = 1 LIMIT 1";
                try (PreparedStatement ps = conn.prepareStatement(sql)) {
                    ps.setString(1, username);
                    ps.setString(2, username);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            int id = rs.getInt("id");
                            String dni = rs.getString("dni");
                            System.out.println(
                                    "Authenticated user: id=" + id + ", dni=" + dni + ", username=" + username);
                            return id;
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error getting authenticated user ID: " + e.getMessage());
            e.printStackTrace();
        }
        return null;
    }}

    

    
    
        
        
                
                
        
        
    

    

    
    
    
    
            
                    
                    
                    
                    
                    
    
        
        
        
            
            
            
            
            
            
            

            

            
            
            
            
            
            
            
            

            
            
            
                
                        
                        
                
                
            
            
        
    
    
    

    
            

    