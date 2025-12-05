package com.asistenciav2.servlet;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.logging.Logger;

@WebServlet("/api/process-attendance")
public class ProcessAttendanceServlet extends HttpServlet {
    private static final Logger logger = Logger.getLogger(ProcessAttendanceServlet.class.getName());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile Process scriptProcess;
    private final AtomicBoolean running = new AtomicBoolean(false);

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        String action = request.getParameter("action");
        if ("status".equals(action)) {
            handleStatus(response);
        } else if ("stream".equals(action)) {
            handleStream(response);
        } else if ("startScript".equals(action)) {
            handleStartScript(request, response);
        } else {
            response.setContentType("application/json");
            response.setCharacterEncoding("UTF-8");
            response.getWriter().write("{\"success\":false,\"message\":\"Acción no soportada\"}");
        }
    }

    private void handleStatus(HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        ObjectMapper mapper = new ObjectMapper();
        java.util.Map<String, Object> result = new java.util.HashMap<>();
        result.put("running", running.get());
        response.getWriter().write(mapper.writeValueAsString(result));
    }

    private void handleStartScript(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        ObjectMapper mapper = new ObjectMapper();
        java.util.Map<String, Object> result = new java.util.HashMap<>();
        if (running.get()) {
            result.put("success", true);
            result.put("message", "Ya hay un proceso en ejecución");
            result.put("running", true);
            response.getWriter().write(mapper.writeValueAsString(result));
            return;
        }

        java.util.List<String> cmd = new java.util.ArrayList<>();
        cmd.add("python3");
        cmd.add("procesarAsistencia.py");
        String fechaInicio = request.getParameter("fechaInicio");
        String fechaFin = request.getParameter("fechaFin");
        String dni = request.getParameter("dni");
        if (fechaInicio != null && !fechaInicio.trim().isEmpty()) {
            cmd.add("--fecha-inicio");
            cmd.add(fechaInicio.trim());
        }
        if (fechaFin != null && !fechaFin.trim().isEmpty()) {
            cmd.add("--fecha-fin");
            cmd.add(fechaFin.trim());
        }
        if (dni != null && !dni.trim().isEmpty()) {
            cmd.add("--dni");
            cmd.add(dni.trim());
        }
        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.directory(new java.io.File(request.getServletContext().getRealPath("/")));
        pb.redirectErrorStream(true);
        try {
            scriptProcess = pb.start();
            running.set(true);
            executor.submit(() -> {
                try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(scriptProcess.getInputStream()))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        // Buffering happens in stream handler
                        synchronized (this) {
                            lastOutput.append(line).append('\n');
                        }
                    }
                    scriptProcess.waitFor();
                } catch (Exception e) {
                    logger.log(Level.SEVERE, "Error leyendo salida de procesarAsistencia.py", e);
                } finally {
                    running.set(false);
                }
            });
            result.put("success", true);
            result.put("message", "Proceso iniciado");
            result.put("running", true);
            response.getWriter().write(mapper.writeValueAsString(result));
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error iniciando procesarAsistencia.py", e);
            result.put("success", false);
            result.put("message", "No se pudo iniciar el proceso");
            response.getWriter().write(mapper.writeValueAsString(result));
        }
    }

    private final StringBuilder lastOutput = new StringBuilder();

    private void handleStream(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType("text/event-stream");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Cache-Control", "no-cache");
        PrintWriter out = response.getWriter();
        out.flush();
        int cursor = 0;
        try {
            while (running.get()) {
                String chunk;
                synchronized (this) {
                    chunk = lastOutput.substring(cursor);
                    cursor = lastOutput.length();
                }
                if (!chunk.isEmpty()) {
                    String[] lines = chunk.split("\n");
                    for (String line : lines) {
                        out.write("data: " + line + "\n\n");
                    }
                    out.flush();
                }
                Thread.sleep(300);
            }
            out.write("data: {\"type\":\"end\"}\n\n");
            out.flush();
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }
}