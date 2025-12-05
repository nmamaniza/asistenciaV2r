package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.YearMonth;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.ArrayList;
import java.util.List;
import java.util.HashMap;

@WebServlet("/api/consolidado-mensual")
public class ConsolidadoMensualServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json; charset=UTF-8");
        
        String anioStr = req.getParameter("anio");
        String mesStr = req.getParameter("mes");
        String modalidad = req.getParameter("modalidad");
        String area = req.getParameter("area");
        String equipo = req.getParameter("equipo");
        String formato = req.getParameter("formato"); // json o csv
        
        int anio = (anioStr != null && !anioStr.isEmpty()) ? Integer.parseInt(anioStr) : java.time.LocalDate.now().getYear();
        int mes = (mesStr != null && !mesStr.isEmpty()) ? Integer.parseInt(mesStr) : java.time.LocalDate.now().getMonthValue();
        
        YearMonth yearMonth = YearMonth.of(anio, mes);
        int daysInMonth = yearMonth.lengthOfMonth();
        
        try (Connection conn = DatabaseConnection.getConnection()) {
            // Primero obtener todas las asignaciones activas
            StringBuilder sql = new StringBuilder();
            sql.append("SELECT ");
            sql.append("    u.dni, ");
            sql.append("    COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre_completo, ");
            sql.append("    ja.modalidad, ");
            sql.append("    ja.cargo, ");
            sql.append("    ja.area, ");
            sql.append("    ja.equipo, ");
            sql.append("    ja.jefe, ");
            sql.append("    ja.fechaini, ");
            sql.append("    ja.fechafin, ");
            sql.append("    ws.descripcion AS horario, ");
            sql.append("    ja.id AS jobassignment_id ");
            sql.append("FROM jobassignments ja ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("JOIN workschedules ws ON ws.id = ja.workschedule_id ");
            sql.append("WHERE ja.estado = 1 ");
            
            // Filtros opcionales
            List<Object> params = new ArrayList<>();
            if (modalidad != null && !modalidad.isEmpty() && !modalidad.equals("TODOS")) {
                sql.append("AND ja.modalidad = ? ");
                params.add(modalidad);
            }
            if (area != null && !area.isEmpty() && !area.equals("TODOS")) {
                sql.append("AND ja.area = ? ");
                params.add(area);
            }
            if (equipo != null && !equipo.isEmpty() && !equipo.equals("TODOS")) {
                sql.append("AND ja.equipo = ? ");
                params.add(equipo);
            }
            
            // Filtrar por asignaciones que estén vigentes en el mes seleccionado
            sql.append("AND (ja.fechaini <= ?) "); // Fecha inicio antes o durante el mes
            sql.append("AND (ja.fechafin IS NULL OR ja.fechafin >= ?) "); // Fecha fin después o nula
            params.add(java.sql.Date.valueOf(yearMonth.atEndOfMonth()));
            params.add(java.sql.Date.valueOf(yearMonth.atDay(1)));
            
            sql.append("ORDER BY u.dni ASC, ja.fechaini DESC");
            
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }
                
                ResultSet rs = ps.executeQuery();
                List<Map<String, Object>> data = new ArrayList<>();
                
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("dni", rs.getString("dni"));
                    row.put("nombre_completo", rs.getString("nombre_completo"));
                    row.put("modalidad", rs.getString("modalidad"));
                    row.put("cargo", rs.getString("cargo"));
                    row.put("area", rs.getString("area"));
                    row.put("equipo", rs.getString("equipo"));
                    row.put("jefe", rs.getString("jefe"));
                    row.put("horario", rs.getString("horario"));
                    row.put("jobassignment_id", rs.getInt("jobassignment_id"));
                    
                    // Obtener asistencias del mes para esta asignación
                    Map<Integer, String> diasAsistencia = obtenerAsistenciasMes(conn, 
                        rs.getInt("jobassignment_id"), anio, mes, daysInMonth);
                    row.put("dias", diasAsistencia);
                    
                    data.add(row);
                }
                
                if ("csv".equalsIgnoreCase(formato)) {
                    exportarCSV(resp, data, daysInMonth, anio, mes);
                } else {
                    exportarJSON(resp, data, daysInMonth, anio, mes);
                }
            }
            
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"" + e.getMessage() + "\"}");
            e.printStackTrace();
        }
    }
    
    private Map<Integer, String> obtenerAsistenciasMes(Connection conn, int jobassignmentId, int anio, int mes, int daysInMonth) throws Exception {
        Map<Integer, String> dias = new HashMap<>();
        
        // Inicializar todos los días como vacíos
        for (int dia = 1; dia <= daysInMonth; dia++) {
            dias.put(dia, "");
        }
        
        String sql = "SELECT fecha, final FROM dailyattendances WHERE jobassignment_id = ? AND anio = ? AND mes = ? AND estado = 1 ORDER BY fecha ASC";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, jobassignmentId);
            ps.setInt(2, anio);
            ps.setInt(3, mes);
            
            ResultSet rs = ps.executeQuery();
            while (rs.next()) {
                java.sql.Date fecha = rs.getDate("fecha");
                String estado = rs.getString("final");
                if (fecha != null && estado != null && !estado.isEmpty()) {
                    int dia = fecha.toLocalDate().getDayOfMonth();
                    dias.put(dia, estado);
                }
            }
        }
        
        return dias;
    }
    
    private void exportarJSON(HttpServletResponse resp, List<Map<String, Object>> data, int daysInMonth, int anio, int mes) throws Exception {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("total", data.size());
        response.put("anio", anio);
        response.put("mes", mes);
        response.put("dias_en_mes", daysInMonth);
        response.put("data", data);
        
        resp.getWriter().write(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(response));
    }
    
    private void exportarCSV(HttpServletResponse resp, List<Map<String, Object>> data, int daysInMonth, int anio, int mes) throws Exception {
        resp.setContentType("text/csv; charset=UTF-8");
        resp.setHeader("Content-Disposition", String.format("attachment; filename=consolidado_mensual_%04d_%02d.csv", anio, mes));
        
        PrintWriter out = resp.getWriter();
        
        // Construir header con días del mes
        StringBuilder header = new StringBuilder("DNI,Nombre Completo,Modalidad,Cargo,Área,Equipo,Jefe,Horario");
        for (int dia = 1; dia <= daysInMonth; dia++) {
            header.append(",D").append(String.format("%02d", dia));
        }
        out.println(header.toString());
        
        // Datos
        for (Map<String, Object> row : data) {
            StringBuilder line = new StringBuilder();
            line.append(escapeCSV(row.get("dni"))).append(",");
            line.append(escapeCSV(row.get("nombre_completo"))).append(",");
            line.append(escapeCSV(row.get("modalidad"))).append(",");
            line.append(escapeCSV(row.get("cargo"))).append(",");
            line.append(escapeCSV(row.get("area"))).append(",");
            line.append(escapeCSV(row.get("equipo"))).append(",");
            line.append(escapeCSV(row.get("jefe"))).append(",");
            line.append(escapeCSV(row.get("horario")));
            
            // Agregar días del mes
            @SuppressWarnings("unchecked")
            Map<Integer, String> dias = (Map<Integer, String>) row.get("dias");
            for (int dia = 1; dia <= daysInMonth; dia++) {
                line.append(",").append(escapeCSV(dias.getOrDefault(dia, "")));
            }
            
            out.println(line.toString());
        }
    }
    
    private String escapeCSV(Object value) {
        if (value == null) return "";
        String str = value.toString();
        if (str.contains(",") || str.contains("\"") || str.contains("\n")) {
            str = str.replace("\"", "\"\"");
            return "\"" + str + "\"";
        }
        return str;
    }
}