package com.asistenciav2.servlet;

import com.asistenciav2.service.BiometricSyncService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.ConcurrentHashMap;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.regex.Pattern;
import java.util.regex.Matcher;
import java.util.logging.Logger;
import java.util.logging.Level;

@WebServlet("/biometric-sync")
public class BiometricSyncServlet extends HttpServlet {
    private static final Logger logger = Logger.getLogger(BiometricSyncServlet.class.getName());
    private BiometricSyncService syncService;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile Process scriptProcess;
    private final LinkedBlockingQueue<String> logQueue = new LinkedBlockingQueue<>(2000);
    private final LinkedBlockingQueue<String> marksQueue = new LinkedBlockingQueue<>(500);
    private final AtomicBoolean running = new AtomicBoolean(false);
    private final Map<String, ArrayDeque<Map<String, String>>> recentMarks = new ConcurrentHashMap<>();
    private final Pattern markPattern = Pattern.compile("ID:\\s*(\\d+)\\s*\\|\\s*Fecha:\\s*([^|]+)\\s*\\|\\s*Reloj:\\s*([^(\\s]+)\\s*\\(([^)]+)\\)");
    private final Map<String, Integer> summaryProcessed = new ConcurrentHashMap<>();
    private final Pattern attemptPattern = Pattern.compile("Conectando a\\s+(\\w+)\\s*\\(([^)]+)\\)");
    private final Pattern connectedPattern = Pattern.compile("Conectado exitosamente a\\s+(\\w+)\\s*\\(([^)]+)\\)");
    private final Pattern dbCountPattern = Pattern.compile("(\\w+):\\s*(\\d+)\\s+marcaciones en BD");
    private final Pattern obtainedCountPattern = Pattern.compile("(\\w+):\\s*(\\d+)\\s+marcaciones obtenidas");
    private final Pattern processedSummaryPattern = Pattern.compile("(\\w+):\\s*(\\d+)\\s+marcaciones nuevas procesadas");
    private final Map<String, Map<String, Object>> deviceStatus = new ConcurrentHashMap<>();
    
    @Override
    public void init() throws ServletException {
        syncService = new BiometricSyncService();
        
        // Configurar desde parámetros de inicialización
        String deviceIp = getInitParameter("deviceIp");
        String devicePort = getInitParameter("devicePort");
        
        if (deviceIp != null) {
            syncService.setDeviceIp(deviceIp);
        }
        
        if (devicePort != null) {
            try {
                syncService.setDevicePort(Integer.parseInt(devicePort));
            } catch (NumberFormatException e) {
                logger.warning("Puerto de dispositivo inválido: " + devicePort);
            }
        }
    }
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        
        String action = request.getParameter("action");
        
        if ("test".equals(action)) {
            handleTestConnection(request, response);
        } else if ("config".equals(action)) {
            handleConfiguration(request, response);
        } else if ("devices".equals(action)) {
            handleGetDevices(request, response);
        } else if ("runScript".equals(action)) {
            handleRunScript(request, response);
        } else if ("startScript".equals(action)) {
            handleStartScript(request, response);
        } else if ("stopScript".equals(action)) {
            handleStopScript(request, response);
        } else if ("stream".equals(action)) {
            handleStream(request, response);
        } else if ("status".equals(action)) {
            handleStatus(request, response);
        } else {
            handleSync(request, response);
        }
    }
    
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        
        String action = request.getParameter("action");
        
        if ("updateConfig".equals(action)) {
            handleUpdateConfiguration(request, response);
        } else {
            handleSync(request, response);
        }
    }
    
    private void handleTestConnection(HttpServletRequest request, HttpServletResponse response) 
            throws IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        try {
            Map<String, Object> result = syncService.testConnection();
            
            ObjectMapper mapper = new ObjectMapper();
            String jsonResponse = mapper.writeValueAsString(result);
            
            response.getWriter().write(jsonResponse);
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error en test de conexión", e);
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\": false, \"message\": \"Error interno del servidor\"}");
        }
    }
    
    private void handleConfiguration(HttpServletRequest request, HttpServletResponse response) 
            throws IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        Map<String, Object> config = new HashMap<>();
        config.put("deviceIp", getInitParameter("deviceIp"));
        config.put("devicePort", getInitParameter("devicePort"));
        
        ObjectMapper mapper = new ObjectMapper();
        String jsonResponse = mapper.writeValueAsString(config);
        
        response.getWriter().write(jsonResponse);
    }
    
    private void handleUpdateConfiguration(HttpServletRequest request, HttpServletResponse response) 
            throws IOException {
        
        String deviceIp = request.getParameter("deviceIp");
        String devicePort = request.getParameter("devicePort");
        
        if (deviceIp != null && !deviceIp.trim().isEmpty()) {
            syncService.setDeviceIp(deviceIp.trim());
        }
        
        if (devicePort != null && !devicePort.trim().isEmpty()) {
            try {
                syncService.setDevicePort(Integer.parseInt(devicePort.trim()));
            } catch (NumberFormatException e) {
                response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
                response.getWriter().write("{\"success\": false, \"message\": \"Puerto inválido\"}");
                return;
            }
        }
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"success\": true, \"message\": \"Configuración actualizada\"}");
    }
    
    private void handleSync(HttpServletRequest request, HttpServletResponse response) 
            throws IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        try {
            Map<String, Object> result = syncService.syncBiometricData();
            
            ObjectMapper mapper = new ObjectMapper();
            String jsonResponse = mapper.writeValueAsString(result);
            
            response.getWriter().write(jsonResponse);
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error en sincronización", e);
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\": false, \"message\": \"Error interno del servidor\"}");
        }
    }
    
    private void handleGetDevices(HttpServletRequest request, HttpServletResponse response) 
            throws IOException {
        
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        try {
            List<BiometricSyncService.BiometricDevice> devices = syncService.getConfiguredDevices();
            
            Map<String, Object> result = new HashMap<>();
            result.put("success", true);
            result.put("devices", devices);
            
            ObjectMapper mapper = new ObjectMapper();
            String jsonResponse = mapper.writeValueAsString(result);
            
            response.getWriter().write(jsonResponse);
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error obteniendo dispositivos", e);
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"success\": false, \"message\": \"Error interno del servidor\"}");
        }
    }

    private void handleRunScript(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        java.util.List<String> cmd = new java.util.ArrayList<>();
        cmd.add("python3");
        cmd.add("sync_checker.py");
        cmd.add("--live");
        String clock = request.getParameter("clock");
        if (clock != null && !clock.trim().isEmpty()) {
            cmd.add("--clock");
            cmd.add(clock.trim());
        }
        String order = request.getParameter("order");
        if (order != null && !order.trim().isEmpty()) {
            cmd.add("--order");
            cmd.add(order.trim());
        }
        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.directory(new java.io.File(request.getServletContext().getRealPath("/")));
        pb.redirectErrorStream(true);
        StringBuilder output = new StringBuilder();
        int exitCode = -1;
        try {
            Process process = pb.start();
            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
            }
            exitCode = process.waitFor();
            ObjectMapper mapper = new ObjectMapper();
            java.util.Map<String, Object> result = new java.util.HashMap<>();
            result.put("success", exitCode == 0);
            result.put("exitCode", exitCode);
            result.put("output", output.toString());
            String jsonResponse = mapper.writeValueAsString(result);
            response.getWriter().write(jsonResponse);
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error ejecutando sync_checker.py", e);
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            ObjectMapper mapper = new ObjectMapper();
            java.util.Map<String, Object> result = new java.util.HashMap<>();
            result.put("success", false);
            result.put("message", "No se pudo ejecutar sync_checker.py");
            result.put("output", output.toString());
            String jsonResponse = mapper.writeValueAsString(result);
            response.getWriter().write(jsonResponse);
        }
    }

    private void handleStartScript(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        if (running.get()) {
            ObjectMapper mapper = new ObjectMapper();
            java.util.Map<String, Object> result = new java.util.HashMap<>();
            result.put("success", true);
            result.put("message", "Ya hay un proceso en ejecución");
            result.put("running", true);
            response.getWriter().write(mapper.writeValueAsString(result));
            return;
        }
        java.util.List<String> cmd = new java.util.ArrayList<>();
        cmd.add("python3");
        cmd.add("sync_checker.py");
        cmd.add("--live");
        String clock = request.getParameter("clock");
        if (clock != null && !clock.trim().isEmpty()) {
            cmd.add("--clock");
            cmd.add(clock.trim());
        }
        String order = request.getParameter("order");
        if (order != null && !order.trim().isEmpty()) {
            cmd.add("--order");
            cmd.add(order.trim());
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
                    while (running.get() && (line = reader.readLine()) != null) {
                        logQueue.offer(line);
                        try {
                            Matcher m;
                            m = attemptPattern.matcher(line);
                            if (m.find()) {
                                String id = m.group(1);
                                String ip = m.group(2);
                                Map<String, Object> st = deviceStatus.getOrDefault(id, new HashMap<>());
                                st.put("id", id);
                                st.put("ip", ip);
                                st.put("status", "Conectando");
                                deviceStatus.put(id, st);
                            }
                            m = connectedPattern.matcher(line);
                            if (m.find()) {
                                String id = m.group(1);
                                String ip = m.group(2);
                                Map<String, Object> st = deviceStatus.getOrDefault(id, new HashMap<>());
                                st.put("id", id);
                                st.put("ip", ip);
                                st.put("status", "Conectado");
                                deviceStatus.put(id, st);
                            }
                            m = dbCountPattern.matcher(line);
                            if (m.find()) {
                                String id = m.group(1);
                                int count = Integer.parseInt(m.group(2));
                                Map<String, Object> st = deviceStatus.getOrDefault(id, new HashMap<>());
                                st.put("id", id);
                                st.put("dbCount", count);
                                deviceStatus.put(id, st);
                            }
                            m = obtainedCountPattern.matcher(line);
                            if (m.find()) {
                                String id = m.group(1);
                                int count = Integer.parseInt(m.group(2));
                                Map<String, Object> st = deviceStatus.getOrDefault(id, new HashMap<>());
                                st.put("id", id);
                                st.put("obtainedCount", count);
                                deviceStatus.put(id, st);
                            }
                        } catch (Exception ignored) {}
                    }
                } catch (Exception e) {
                    logger.log(Level.FINE, "Lectura de proceso cerrada", e);
                }
            });
            executor.submit(() -> {
                try {
                    int code = scriptProcess.waitFor();
                    running.set(false);
                    logQueue.offer("Proceso finalizado. Código: " + code);
                } catch (InterruptedException e) {
                    running.set(false);
                }
            });
            ObjectMapper mapper = new ObjectMapper();
            java.util.Map<String, Object> result = new java.util.HashMap<>();
            result.put("success", true);
            result.put("message", "Proceso iniciado");
            result.put("running", true);
            response.getWriter().write(mapper.writeValueAsString(result));
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error iniciando sync_checker.py", e);
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            ObjectMapper mapper = new ObjectMapper();
            java.util.Map<String, Object> result = new java.util.HashMap<>();
            result.put("success", false);
            result.put("message", "No se pudo iniciar sync_checker.py");
            response.getWriter().write(mapper.writeValueAsString(result));
        }
    }

    private void handleStopScript(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        if (scriptProcess != null && running.get()) {
            try {
                scriptProcess.destroy();
            } catch (Exception ignored) {}
            running.set(false);
        }
        ObjectMapper mapper = new ObjectMapper();
        java.util.Map<String, Object> result = new java.util.HashMap<>();
        result.put("success", true);
        result.put("message", "Proceso detenido");
        response.getWriter().write(mapper.writeValueAsString(result));
    }

    private void handleStream(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType("text/event-stream");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Cache-Control", "no-cache");
        java.io.PrintWriter writer = response.getWriter();
        try {
            int idle = 0;
            while (running.get() || !logQueue.isEmpty() || idle < 60) {
                boolean sent = false;
                String line = logQueue.poll(1, TimeUnit.SECONDS);
                if (line != null) {
                    writer.print("data: " + line + "\n\n");
                    writer.flush();
                    sent = true;
                }
                if (sent) {
                    idle = 0;
                } else {
                    idle++;
                }
            }
            writer.print("data: {\"type\":\"end\"}\n\n");
            writer.flush();
        } catch (Exception e) {
            logger.log(Level.FINE, "SSE cerrado", e);
        }
    }
    private void handleStatus(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        ObjectMapper mapper = new ObjectMapper();
        Map<String, Object> result = new HashMap<>();
        List<Map<String, Object>> devices = new ArrayList<>();
        for (Map.Entry<String, Map<String, Object>> e : deviceStatus.entrySet()) {
            Map<String, Object> d = new HashMap<>(e.getValue());
            d.putIfAbsent("id", e.getKey());
            devices.add(d);
        }
        result.put("success", true);
        result.put("running", running.get());
        result.put("devices", devices);
        response.getWriter().write(mapper.writeValueAsString(result));
    }
}
