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
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.ArrayList;
import java.util.List;

@WebServlet("/api/jobassignments-report")
public class JobAssignmentsReportServlet extends HttpServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        resp.setContentType("application/json; charset=UTF-8");
        
        String modalidad = req.getParameter("modalidad");
        String cargo = req.getParameter("cargo");
        String area = req.getParameter("area");
        String equipo = req.getParameter("equipo");
        String estado = req.getParameter("estado");
        String formato = req.getParameter("formato"); // json o csv
        
        try (Connection conn = DatabaseConnection.getConnection()) {
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
            sql.append("    ja.salario, ");
            sql.append("    ja.observaciones, ");
            sql.append("    ja.estado, ");
            sql.append("    ws.descripcion AS horario, ");
            sql.append("    ws.horaini, ");
            sql.append("    ws.horafin ");
            sql.append("FROM jobassignments ja ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("JOIN workschedules ws ON ws.id = ja.workschedule_id ");
            sql.append("WHERE 1=1 ");
            
            List<Object> params = new ArrayList<>();
            
            if (modalidad != null && !modalidad.isEmpty() && !modalidad.equals("TODOS")) {
                sql.append("AND ja.modalidad = ? ");
                params.add(modalidad);
            }
            
            if (cargo != null && !cargo.isEmpty()) {
                sql.append("AND ja.cargo ILIKE ? ");
                params.add("%" + cargo + "%");
            }
            
            if (area != null && !area.isEmpty() && !area.equals("TODOS")) {
                sql.append("AND ja.area = ? ");
                params.add(area);
            }
            
            if (equipo != null && !equipo.isEmpty() && !equipo.equals("TODOS")) {
                sql.append("AND ja.equipo = ? ");
                params.add(equipo);
            }
            
            if (estado != null && !estado.isEmpty() && !estado.equals("TODOS")) {
                sql.append("AND ja.estado = ? ");
                params.add(Integer.parseInt(estado));
            }
            
            sql.append("ORDER BY u.dni ASC, ja.fechaini DESC");
            
            try (PreparedStatement ps = conn.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }
                
                ResultSet rs = ps.executeQuery();
                
                if ("csv".equalsIgnoreCase(formato)) {
                    exportToCSV(resp, rs);
                } else {
                    exportToJSON(resp, rs);
                }
            }
            
        } catch (Exception e) {
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"" + e.getMessage() + "\"}");
            e.printStackTrace();
        }
    }
    
    private void exportToJSON(HttpServletResponse resp, ResultSet rs) throws Exception {
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
            row.put("fechaini", rs.getDate("fechaini"));
            row.put("fechafin", rs.getDate("fechafin"));
            row.put("salario", rs.getBigDecimal("salario"));
            row.put("observaciones", rs.getString("observaciones"));
            row.put("estado", rs.getInt("estado"));
            row.put("horario", rs.getString("horario"));
            row.put("horaini", rs.getTime("horaini"));
            row.put("horafin", rs.getTime("horafin"));
            
            // Estado actual (vigente o no)
            java.sql.Date fechafin = rs.getDate("fechafin");
            String estadoActual = (fechafin == null) ? "VIGENTE" : "FINALIZADO";
            row.put("estado_actual", estadoActual);
            
            data.add(row);
        }
        
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("success", true);
        response.put("total", data.size());
        response.put("data", data);
        
        resp.getWriter().write(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(response));
    }
    
    private void exportToCSV(HttpServletResponse resp, ResultSet rs) throws Exception {
        resp.setContentType("text/csv; charset=UTF-8");
        resp.setHeader("Content-Disposition", "attachment; filename=reporte_asignaciones_trabajo.csv");
        
        PrintWriter out = resp.getWriter();
        
        // Header
        out.println("DNI,Nombre Completo,Modalidad,Cargo,Área,Equipo,Jefe,Fecha Inicio,Fecha Fin,Salario,Observaciones,Estado,Horario,Hora Inicio,Hora Fin,Estado Actual");
        
        while (rs.next()) {
            StringBuilder row = new StringBuilder();
            row.append(escapeCSV(rs.getString("dni"))).append(",");
            row.append(escapeCSV(rs.getString("nombre_completo"))).append(",");
            row.append(escapeCSV(rs.getString("modalidad"))).append(",");
            row.append(escapeCSV(rs.getString("cargo"))).append(",");
            row.append(escapeCSV(rs.getString("area"))).append(",");
            row.append(escapeCSV(rs.getString("equipo"))).append(",");
            row.append(escapeCSV(rs.getString("jefe"))).append(",");
            row.append(escapeCSV(rs.getDate("fechaini"))).append(",");
            row.append(escapeCSV(rs.getDate("fechafin"))).append(",");
            row.append(escapeCSV(rs.getBigDecimal("salario"))).append(",");
            row.append(escapeCSV(rs.getString("observaciones"))).append(",");
            row.append(escapeCSV(rs.getInt("estado") == 1 ? "ACTIVO" : "INACTIVO")).append(",");
            row.append(escapeCSV(rs.getString("horario"))).append(",");
            row.append(escapeCSV(rs.getTime("horaini"))).append(",");
            row.append(escapeCSV(rs.getTime("horafin"))).append(",");
            
            java.sql.Date fechafin = rs.getDate("fechafin");
            String estadoActual = (fechafin == null) ? "VIGENTE" : "FINALIZADO";
            row.append(escapeCSV(estadoActual));
            
            out.println(row.toString());
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