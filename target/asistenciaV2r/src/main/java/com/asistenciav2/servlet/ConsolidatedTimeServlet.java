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
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.*;

@WebServlet("/api/consolidated-time")
public class ConsolidatedTimeServlet extends HttpServlet {
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
            LocalDate now = LocalDate.now();
            anio = now.getYear();
            mes = now.getMonthValue();
        }

        Map<String, Map<String, Object>> rows = new LinkedHashMap<>();

        try (Connection conn = DatabaseConnection.getConnection()) {
            final int anioVal = anio;
            final int mesVal = mes;
            final int daysInMonth = YearMonth.of(anioVal, mesVal).lengthOfMonth();

            // Obtener días laborables del mes (excluyendo sábados, domingos y feriados)
            int diasLaborables = getDiasLaborables(conn, anioVal, mesVal);

            StringBuilder sql = new StringBuilder();
            sql.append("SELECT u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("ja.modalidad, ja.cargo, ja.area, ja.id as job_id, ");
            sql.append("da.fecha, da.horaini, da.horafin, da.minlab, ");
            sql.append("ws.horaini as schedule_ini, ws.horas_jornada "); // Fetch scheduled start time and work hours
            sql.append("FROM jobassignments ja ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("JOIN workschedules ws ON ws.id = ja.workschedule_id "); // Join workschedules
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

                while (rs.next()) {
                    String dni = rs.getString("dni");
                    String nombre = rs.getString("nombre");
                    String modalidad = rs.getString("modalidad");
                    String cargo = rs.getString("cargo");
                    String area = rs.getString("area");
                    long jobId = rs.getLong("job_id");

                    // Extract horas_jornada here to avoid SQLException in lambda
                    int horasJornadaRaw = rs.getInt("horas_jornada");

                    String rowKey = dni + "_" + jobId;

                    Map<String, Object> row = rows.computeIfAbsent(rowKey, k -> {
                        Map<String, Object> m = new LinkedHashMap<>();
                        m.put("dni", dni);
                        m.put("nombre", nombre);
                        m.put("modalidad", modalidad);
                        m.put("cargo", cargo != null ? cargo : "");
                        m.put("area", area != null ? area : "");

                        // Inicializar columnas para cada día
                        for (int d = 1; d <= daysInMonth; d++) {
                            String dayKey = String.valueOf(d);
                            m.put("ing" + dayKey, "");
                            m.put("sal" + dayKey, "");
                            m.put("tot" + dayKey, "");
                        }

                        int horasJornada = horasJornadaRaw;
                        if (horasJornada <= 0)
                            horasJornada = 8; // Default to 8 hours if not set

                        m.put("totalMinutos", 0);
                        m.put("diasLaborables", diasLaborables);
                        m.put("minutosEsperados", diasLaborables * horasJornada * 60);

                        return m;
                    });

                    java.sql.Date f = rs.getDate("fecha");
                    if (f != null) {
                        LocalDate ld = f.toLocalDate();
                        int day = ld.getDayOfMonth();
                        String dayKey = String.valueOf(day);

                        java.sql.Time horaini = rs.getTime("horaini");
                        java.sql.Time horafin = rs.getTime("horafin");
                        java.sql.Time scheduleIni = rs.getTime("schedule_ini");

                        // Use calculated minutes instead of database minlab
                        int calculatedMinLab = 0;

                        if (horafin != null) {
                            row.put("sal" + dayKey, horafin.toString().substring(0, 5)); // HH:mm

                            if (horaini != null) {
                                row.put("ing" + dayKey, horaini.toString().substring(0, 5)); // HH:mm

                                // Calculate minutes worked based on schedule using LocalTime
                                LocalTime ltIni = horaini.toLocalTime().truncatedTo(ChronoUnit.MINUTES);
                                LocalTime ltFin = horafin.toLocalTime().truncatedTo(ChronoUnit.MINUTES);

                                LocalTime effectiveStart = ltIni;
                                if (scheduleIni != null) {
                                    LocalTime ltSched = scheduleIni.toLocalTime().truncatedTo(ChronoUnit.MINUTES);
                                    if (ltIni.isBefore(ltSched)) {
                                        effectiveStart = ltSched;
                                    }
                                }

                                if (ltFin.isAfter(effectiveStart)) {
                                    long minutes = ChronoUnit.MINUTES.between(effectiveStart, ltFin);
                                    calculatedMinLab = (int) minutes;
                                }
                            }
                        } else if (horaini != null) {
                            row.put("ing" + dayKey, horaini.toString().substring(0, 5)); // HH:mm
                        }

                        if (calculatedMinLab > 0) {
                            int horas = calculatedMinLab / 60;
                            int minutos = calculatedMinLab % 60;
                            row.put("tot" + dayKey, String.format("%d:%02d", horas, minutos));

                            // Acumular minutos totales
                            int totalActual = (int) row.get("totalMinutos");
                            row.put("totalMinutos", totalActual + calculatedMinLab);
                        }
                    }
                }
            }

            // Calcular tiempo total y por compensar para cada fila
            for (Map<String, Object> row : rows.values()) {
                int totalMinutos = (int) row.get("totalMinutos");
                int minutosEsperados = (int) row.get("minutosEsperados");

                // Convertir a formato HH:mm
                int horasTotal = totalMinutos / 60;
                int minutosTotal = totalMinutos % 60;
                row.put("tiempoTotal", String.format("%d:%02d", horasTotal, minutosTotal));

                // Calcular por compensar (puede ser negativo si trabajó de más)
                int porCompensar = minutosEsperados - totalMinutos;
                int horasCompensar = Math.abs(porCompensar) / 60;
                int minutosCompensar = Math.abs(porCompensar) % 60;
                String signo = porCompensar >= 0 ? "" : "-";
                row.put("porCompensar", String.format("%s%d:%02d", signo, horasCompensar, minutosCompensar));

                // Remover campos auxiliares
                row.remove("totalMinutos");
                row.remove("minutosEsperados");
            }

        } catch (SQLException e) {
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("{\"success\":false,\"message\":\"Error de servidor: " + e.getMessage() + "\"}");
            return;
        }

        List<Map<String, Object>> out = new ArrayList<>(rows.values());
        ObjectMapper mapper = new ObjectMapper();
        resp.getWriter().write(mapper.writeValueAsString(out));
    }

    /**
     * Calcula el número de días laborables en un mes (excluyendo sábados, domingos
     * y feriados)
     */
    private int getDiasLaborables(Connection conn, int anio, int mes) throws SQLException {
        String sql = "SELECT COUNT(*) FROM calendardays " +
                "WHERE EXTRACT(YEAR FROM fecha) = ? " +
                "AND EXTRACT(MONTH FROM fecha) = ? " +
                "AND estado = 1"; // 1 = laborable

        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, anio);
            ps.setInt(2, mes);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                return rs.getInt(1);
            }
        }

        // Si no hay datos en calendardays, calcular manualmente
        YearMonth yearMonth = YearMonth.of(anio, mes);
        int diasLaborables = 0;
        for (int d = 1; d <= yearMonth.lengthOfMonth(); d++) {
            LocalDate fecha = LocalDate.of(anio, mes, d);
            int dayOfWeek = fecha.getDayOfWeek().getValue(); // 1=Lunes, 7=Domingo
            if (dayOfWeek != 6 && dayOfWeek != 7) { // No es sábado ni domingo
                diasLaborables++;
            }
        }
        return diasLaborables;
    }
}
