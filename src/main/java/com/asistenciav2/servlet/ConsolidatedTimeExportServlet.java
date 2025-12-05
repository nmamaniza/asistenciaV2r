package com.asistenciav2.servlet;

import com.asistenciav2.util.DatabaseConnection;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.apache.poi.ss.usermodel.*;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

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

@WebServlet("/api/consolidated-time-export")
public class ConsolidatedTimeExportServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String anioStr = req.getParameter("anio");
        String mesStr = req.getParameter("mes");
        String q = req.getParameter("q");

        Integer anio, mes;
        try {
            anio = (anioStr != null && !anioStr.isEmpty()) ? Integer.parseInt(anioStr) : null;
            mes = (mesStr != null && !mesStr.isEmpty()) ? Integer.parseInt(mesStr) : null;
        } catch (NumberFormatException e) {
            resp.setStatus(HttpServletResponse.SC_BAD_REQUEST);
            resp.getWriter().write("Parámetros de año/mes inválidos");
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

            int diasLaborables = getDiasLaborables(conn, anioVal, mesVal);

            StringBuilder sql = new StringBuilder();
            sql.append("SELECT u.dni, COALESCE(u.nombre,'') || ' ' || COALESCE(u.apellidos,'') AS nombre, ");
            sql.append("ja.modalidad, ja.cargo, ja.area, ja.id as job_id, ");
            sql.append("da.fecha, da.horaini, da.horafin, da.minlab, ");
            sql.append("ws.horaini as schedule_ini, ws.horas_jornada ");
            sql.append("FROM jobassignments ja ");
            sql.append("JOIN users u ON u.id = ja.user_id ");
            sql.append("JOIN workschedules ws ON ws.id = ja.workschedule_id ");
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

                    // Extract horas_jornada here
                    int horasJornadaRaw = rs.getInt("horas_jornada");

                    String rowKey = dni + "_" + jobId;

                    Map<String, Object> row = rows.computeIfAbsent(rowKey, k -> {
                        Map<String, Object> m = new LinkedHashMap<>();
                        m.put("dni", dni);
                        m.put("nombre", nombre);
                        m.put("modalidad", modalidad);
                        m.put("cargo", cargo != null ? cargo : "");
                        m.put("area", area != null ? area : "");

                        for (int d = 1; d <= daysInMonth; d++) {
                            String dayKey = String.valueOf(d);
                            m.put("ing" + dayKey, "");
                            m.put("sal" + dayKey, "");
                            m.put("tot" + dayKey, "");
                        }

                        int horasJornada = horasJornadaRaw;
                        if (horasJornada <= 0)
                            horasJornada = 8;

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

                        int calculatedMinLab = 0;

                        if (horafin != null) {
                            row.put("sal" + dayKey, horafin.toString().substring(0, 5));

                            if (horaini != null) {
                                row.put("ing" + dayKey, horaini.toString().substring(0, 5));

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
                            row.put("ing" + dayKey, horaini.toString().substring(0, 5));
                        }

                        if (calculatedMinLab > 0) {
                            int horas = calculatedMinLab / 60;
                            int minutos = calculatedMinLab % 60;
                            row.put("tot" + dayKey, String.format("%d:%02d", horas, minutos));

                            int totalActual = (int) row.get("totalMinutos");
                            row.put("totalMinutos", totalActual + calculatedMinLab);
                        }
                    }
                }
            }

            for (Map<String, Object> row : rows.values()) {
                int totalMinutos = (int) row.get("totalMinutos");
                int minutosEsperados = (int) row.get("minutosEsperados");

                int horasTotal = totalMinutos / 60;
                int minutosTotal = totalMinutos % 60;
                row.put("tiempoTotal", String.format("%d:%02d", horasTotal, minutosTotal));

                int porCompensar = minutosEsperados - totalMinutos;
                int horasCompensar = Math.abs(porCompensar) / 60;
                int minutosCompensar = Math.abs(porCompensar) % 60;
                String signo = porCompensar >= 0 ? "" : "-";
                row.put("porCompensar", String.format("%s%d:%02d", signo, horasCompensar, minutosCompensar));
            }

            // Generar Excel
            generateExcel(resp, rows, anioVal, mesVal, daysInMonth);

        } catch (SQLException e) {
            e.printStackTrace();
            resp.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            resp.getWriter().write("Error de servidor: " + e.getMessage());
        }
    }

    private void generateExcel(HttpServletResponse resp, Map<String, Map<String, Object>> rows,
            int anio, int mes, int daysInMonth) throws IOException {
        Workbook workbook = new XSSFWorkbook();
        Sheet sheet = workbook.createSheet("Consolidado Tiempo");

        // Estilos
        CellStyle headerStyle = workbook.createCellStyle();
        Font headerFont = workbook.createFont();
        headerFont.setBold(true);
        headerFont.setColor(IndexedColors.WHITE.getIndex());
        headerStyle.setFont(headerFont);
        headerStyle.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        headerStyle.setAlignment(HorizontalAlignment.CENTER);
        headerStyle.setBorderBottom(BorderStyle.THIN);
        headerStyle.setBorderTop(BorderStyle.THIN);
        headerStyle.setBorderLeft(BorderStyle.THIN);
        headerStyle.setBorderRight(BorderStyle.THIN);

        CellStyle dataStyle = workbook.createCellStyle();
        dataStyle.setBorderBottom(BorderStyle.THIN);
        dataStyle.setBorderTop(BorderStyle.THIN);
        dataStyle.setBorderLeft(BorderStyle.THIN);
        dataStyle.setBorderRight(BorderStyle.THIN);

        // Crear encabezado
        Row headerRow = sheet.createRow(0);
        int colIdx = 0;

        // Columnas fijas
        createHeaderCell(headerRow, colIdx++, "DNI", headerStyle);
        createHeaderCell(headerRow, colIdx++, "Nombre", headerStyle);
        createHeaderCell(headerRow, colIdx++, "Modalidad", headerStyle);
        createHeaderCell(headerRow, colIdx++, "Cargo", headerStyle);
        createHeaderCell(headerRow, colIdx++, "Área", headerStyle);

        // Columnas por día
        for (int d = 1; d <= daysInMonth; d++) {
            createHeaderCell(headerRow, colIdx++, "Ing " + d, headerStyle);
            createHeaderCell(headerRow, colIdx++, "Sal " + d, headerStyle);
            createHeaderCell(headerRow, colIdx++, "Tot " + d, headerStyle);
        }

        // Columnas finales
        createHeaderCell(headerRow, colIdx++, "Tiempo Total", headerStyle);
        createHeaderCell(headerRow, colIdx++, "Por Compensar", headerStyle);

        // Llenar datos
        int rowIdx = 1;
        for (Map<String, Object> row : rows.values()) {
            Row dataRow = sheet.createRow(rowIdx++);
            colIdx = 0;

            createDataCell(dataRow, colIdx++, (String) row.get("dni"), dataStyle);
            createDataCell(dataRow, colIdx++, (String) row.get("nombre"), dataStyle);
            createDataCell(dataRow, colIdx++, (String) row.get("modalidad"), dataStyle);
            createDataCell(dataRow, colIdx++, (String) row.get("cargo"), dataStyle);
            createDataCell(dataRow, colIdx++, (String) row.get("area"), dataStyle);

            for (int d = 1; d <= daysInMonth; d++) {
                String dayKey = String.valueOf(d);
                createDataCell(dataRow, colIdx++, (String) row.get("ing" + dayKey), dataStyle);
                createDataCell(dataRow, colIdx++, (String) row.get("sal" + dayKey), dataStyle);
                createDataCell(dataRow, colIdx++, (String) row.get("tot" + dayKey), dataStyle);
            }

            createDataCell(dataRow, colIdx++, (String) row.get("tiempoTotal"), dataStyle);
            createDataCell(dataRow, colIdx++, (String) row.get("porCompensar"), dataStyle);
        }

        // Ajustar ancho de columnas
        for (int i = 0; i < 5; i++) {
            sheet.autoSizeColumn(i);
        }

        // Configurar respuesta
        resp.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        resp.setHeader("Content-Disposition",
                "attachment; filename=consolidado_tiempo_" + anio + "_" + String.format("%02d", mes) + ".xlsx");

        workbook.write(resp.getOutputStream());
        workbook.close();
    }

    private void createHeaderCell(Row row, int col, String value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void createDataCell(Row row, int col, String value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(value != null ? value : "");
        cell.setCellStyle(style);
    }

    private int getDiasLaborables(Connection conn, int anio, int mes) throws SQLException {
        String sql = "SELECT COUNT(*) FROM calendardays " +
                "WHERE EXTRACT(YEAR FROM fecha) = ? " +
                "AND EXTRACT(MONTH FROM fecha) = ? " +
                "AND estado = 1";

        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, anio);
            ps.setInt(2, mes);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                return rs.getInt(1);
            }
        }

        YearMonth yearMonth = YearMonth.of(anio, mes);
        int diasLaborables = 0;
        for (int d = 1; d <= yearMonth.lengthOfMonth(); d++) {
            LocalDate fecha = LocalDate.of(anio, mes, d);
            int dayOfWeek = fecha.getDayOfWeek().getValue();
            if (dayOfWeek != 6 && dayOfWeek != 7) {
                diasLaborables++;
            }
        }
        return diasLaborables;
    }
}
