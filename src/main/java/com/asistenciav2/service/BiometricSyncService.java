package com.asistenciav2.service;

import com.asistenciav2.util.DatabaseConnection;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.asistenciav2.biometric.ZKTecoProtocol;

import java.io.*;
import java.net.Socket;
import java.sql.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.logging.Logger;
import java.util.logging.Level;

public class BiometricSyncService {
    private static final Logger logger = Logger.getLogger(BiometricSyncService.class.getName());
    private static final DateTimeFormatter DATE_TIME_FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");
    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd");
    private static final DateTimeFormatter TIME_FORMATTER = DateTimeFormatter.ofPattern("HH:mm");
    
    // Campos de configuración
    private String deviceIp = "172.16.250.3"; // IP por defecto del reloj1
    private int devicePort = 4370;

    public static class SyncStats {
        public int totalRecords = 0;
        public int newRecords = 0;
        public int duplicates = 0;
        public int errors = 0;
        public Map<String, Object> lastRecord = null;
        
        public Map<String, Object> toMap() {
            Map<String, Object> map = new HashMap<>();
            map.put("totalRecords", totalRecords);
            map.put("newRecords", newRecords);
            map.put("duplicates", duplicates);
            map.put("errors", errors);
            map.put("lastRecord", lastRecord);
            return map;
        }
    }
    
    public static class BiometricDevice {
        public Integer id;  // Cambiado de String a Integer
        public String ip;
        public int port;
        public int timeout;
        public int password;
        
        public BiometricDevice(Integer id, String ip, int port, int timeout, int password) {
            this.id = id;
            this.ip = ip;
            this.port = port;
            this.timeout = timeout;
            this.password = password;
        }
    }
    
    public SyncStats syncBiometricData(BiometricDevice device) {
        SyncStats stats = new SyncStats();
        ZKTecoProtocol protocol = null;
        
        try {
            logger.info("Conectando a dispositivo " + device.id + " (" + device.ip + ")");
            
            // Crear instancia del protocolo ZKTeco con contraseña
            protocol = new ZKTecoProtocol(device.ip, device.port, device.password);
            
            // Conectar al dispositivo con logging detallado
            logger.info("Intentando conexión ZKTeco a " + device.ip + ":" + device.port);
            if (!protocol.connect()) {
                logger.severe("FALLO: No se pudo conectar al dispositivo " + device.id);
                logger.severe("Verifique: 1) Protocolo ZKTeco, 2) Password requerido, 3) Versión firmware");
                stats.errors++;
                return stats;
            }
            
            logger.info("✅ Conexión ZKTeco exitosa, obteniendo registros...");
            // Obtener último timestamp sincronizado
            LocalDateTime lastSync = getLastSyncTimestamp(device.id);
            logger.info("Último registro sincronizado: " + lastSync);
            
            // Obtener registros de asistencia del dispositivo
            List<ZKTecoProtocol.AttendanceRecord> zkRecords = protocol.getAttendanceRecords();
            logger.info("Se obtuvieron " + zkRecords.size() + " registros del dispositivo " + device.id);
            
            // Convertir registros ZKTeco al formato esperado por el sistema
            List<Map<String, Object>> attendanceRecords = new ArrayList<>();
            for (ZKTecoProtocol.AttendanceRecord zkRecord : zkRecords) {
                Map<String, Object> record = new HashMap<>();
                
                // Mapear correctamente los datos del ZKTeco
                String dni = String.valueOf(zkRecord.getUserId()); // ID del usuario como DNI
                String nombre = "Usuario_" + zkRecord.getUserId(); // Nombre basado en ID
                LocalDateTime fechaHora = zkRecord.getTimestamp(); // Timestamp completo
                
                record.put("dni", dni);
                record.put("nombre", nombre);
                record.put("fechahora", fechaHora);
                
                // Logging para verificar datos
                logger.info("Registro ZKTeco: DNI=" + dni + ", Nombre=" + nombre + ", FechaHora=" + fechaHora + ", InOut=" + zkRecord.getInOutMode());
                
                attendanceRecords.add(record);
            }
            stats.totalRecords = attendanceRecords.size();
            
            LocalDateTime now = LocalDateTime.now();
            
            for (Map<String, Object> record : attendanceRecords) {
                try {
                    String dni = (String) record.get("dni");
                    String nombre = (String) record.get("nombre");
                    LocalDateTime fechaHora = (LocalDateTime) record.get("fechahora");
                    
                    // Filtrar registros más recientes que el último sincronizado
                    if (lastSync != null && !fechaHora.isAfter(lastSync)) {
                        stats.duplicates++;
                        continue;
                    }
                    
                    // Verificar si el registro ya existe
                    if (recordExists(dni, fechaHora, device.id)) {
                        stats.duplicates++;
                        continue;
                    }
                    
                    // Insertar nuevo registro
                    if (insertAttendance(dni, nombre, fechaHora, device.id, now)) {
                        stats.newRecords++;
                        
                        // Actualizar último registro
                        Map<String, Object> lastRecord = new HashMap<>();
                        lastRecord.put("dni", dni);
                        lastRecord.put("nombre", nombre);
                        lastRecord.put("fechahora", fechaHora.format(DATE_TIME_FORMATTER));
                        lastRecord.put("fecha", fechaHora.format(DATE_FORMATTER));
                        lastRecord.put("hora", fechaHora.format(TIME_FORMATTER));
                        stats.lastRecord = lastRecord;
                        
                        logger.info("Nuevo registro: DNI " + dni + " - " + nombre + " - " + fechaHora.format(DATE_TIME_FORMATTER));
                    } else {
                        stats.errors++;
                    }
                    
                } catch (Exception e) {
                    logger.log(Level.SEVERE, "Error procesando registro: " + e.getMessage(), e);
                    stats.errors++;
                }
            }
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error en sincronización: " + e.getMessage(), e);
            stats.errors++;
        } finally {
            // Cerrar la conexión con el dispositivo
            if (protocol != null) {
                try {
                    protocol.disconnect();
                } catch (Exception e) {
                    logger.log(Level.WARNING, "Error cerrando conexión: " + e.getMessage(), e);
                }
            }
        }
        
        return stats;
    }
    
    private LocalDateTime getLastSyncTimestamp(Integer clockId) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT MAX(fechahora) FROM punch_events WHERE clock_id = ?";
            PreparedStatement stmt = conn.prepareStatement(sql);
            stmt.setInt(1, clockId);
            ResultSet rs = stmt.executeQuery();
            
            if (rs.next()) {
                Timestamp timestamp = rs.getTimestamp(1);
                if (timestamp != null) {
                    return timestamp.toLocalDateTime();
                }
            }
            
            // Si no hay registros previos, retornar hace 24 horas para obtener registros recientes
            return LocalDateTime.now().minusHours(24);
            
        } catch (SQLException e) {
            logger.log(Level.SEVERE, "Error obteniendo último timestamp: " + e.getMessage(), e);
            return LocalDateTime.now().minusHours(24);
        }
    }
    
    private boolean recordExists(String dni, LocalDateTime fechaHora, Integer clockId) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT 1 FROM punch_events WHERE dni = ? AND fechahora = ? AND clock_id = ?";
            PreparedStatement stmt = conn.prepareStatement(sql);
            stmt.setString(1, dni);
            stmt.setTimestamp(2, Timestamp.valueOf(fechaHora));
            stmt.setInt(3, clockId);
            
            ResultSet rs = stmt.executeQuery();
            return rs.next();
        } catch (SQLException e) {
            logger.log(Level.SEVERE, "Error verificando existencia de registro: " + e.getMessage(), e);
            return true;
        }
    }
    
    private boolean insertAttendance(String dni, String nombre, LocalDateTime fechaHora, Integer clockId, LocalDateTime now) {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "INSERT INTO punch_events (dni, nombre, fechahora, fecha, hora, clock_id, estado) VALUES (?, ?, ?, ?, ?, ?, ?)";
            PreparedStatement stmt = conn.prepareStatement(sql);
            
            stmt.setString(1, dni);                                    // DNI del usuario
            stmt.setString(2, nombre);                                  // Nombre del usuario
            stmt.setTimestamp(3, Timestamp.valueOf(fechaHora));         // fechahora completa
            stmt.setDate(4, java.sql.Date.valueOf(fechaHora.toLocalDate())); // solo fecha
            stmt.setTime(5, Time.valueOf(fechaHora.toLocalTime()));     // solo hora
            stmt.setInt(6, clockId);                                   // ID del reloj como INTEGER
            stmt.setInt(7, 1);                                         // estado como INTEGER (1 = ACTIVO)
            
            logger.info("Insertando: DNI=" + dni + ", Nombre=" + nombre + ", FechaHora=" + fechaHora + ", ClockId=" + clockId);
            
            return stmt.executeUpdate() > 0;
            
        } catch (SQLException e) {
            logger.log(Level.SEVERE, "Error insertando registro: " + e.getMessage(), e);
            return false;
        }
    }
    
   
    public List<BiometricDevice> getConfiguredDevices() {
        List<BiometricDevice> devices = new ArrayList<>();
        
        // Configuración actualizada con las IPs correctas y IDs 1 y 2
        devices.add(new BiometricDevice(1, "172.16.250.3", 4370, 5, 0));
        devices.add(new BiometricDevice(2, "172.16.250.4", 4370, 5, 0));
        
        return devices;
    }
    
    /**
     * Configura la IP del dispositivo
     */
    public void setDeviceIp(String deviceIp) {
        this.deviceIp = deviceIp;
    }
    
    /**
     * Configura el puerto del dispositivo
     */
    public void setDevicePort(int devicePort) {
        this.devicePort = devicePort;
    }
    
    /**
     * Prueba la conexión con el dispositivo
     */
    public Map<String, Object> testConnection() {
        Map<String, Object> result = new HashMap<>();
        Socket socket = null;
        
        try {
            logger.info("Probando conexión a " + deviceIp + ":" + devicePort);
            
            socket = new Socket(deviceIp, devicePort);
            socket.setSoTimeout(5000); // 5 segundos timeout
            
            result.put("success", true);
            result.put("message", "Conexión exitosa a " + deviceIp);
            result.put("deviceIp", deviceIp);
            result.put("devicePort", devicePort);
            result.put("timestamp", LocalDateTime.now().format(DATE_TIME_FORMATTER));
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error en test de conexión: " + e.getMessage(), e);
            result.put("success", false);
            result.put("message", "Error de conexión a " + deviceIp + ": " + e.getMessage());
            result.put("deviceIp", deviceIp);
            result.put("devicePort", devicePort);
        } finally {
            if (socket != null) {
                try {
                    socket.close();
                } catch (IOException e) {
                    logger.log(Level.WARNING, "Error cerrando socket: " + e.getMessage(), e);
                }
            }
        }
        
        return result;
    }
    
    /**
     * Sincroniza datos biométricos sin parámetros (usa configuración por defecto)
     */
    public Map<String, Object> syncBiometricData() {
        BiometricDevice defaultDevice = new BiometricDevice(0, deviceIp, devicePort, 5, 0);
        SyncStats stats = syncBiometricData(defaultDevice);
        
        Map<String, Object> result = new HashMap<>();
        result.put("success", stats.errors == 0);
        result.put("message", stats.errors == 0 ? "Sincronización completada" : "Sincronización con errores");
        result.put("totalRecords", stats.totalRecords);
        result.put("newRecords", stats.newRecords);
        result.put("duplicates", stats.duplicates);
        result.put("errors", stats.errors);
        result.put("lastRecord", stats.lastRecord);
        result.put("timestamp", LocalDateTime.now().format(DATE_TIME_FORMATTER));
        result.put("deviceIp", deviceIp);
        result.put("devicePort", devicePort);
        
        return result;
    }
    
    public Map<String, Object> syncAllDevices() {
        List<BiometricDevice> devices = getConfiguredDevices();
        Map<String, Object> globalStats = new HashMap<>();
        
        int totalRecords = 0;
        int totalNewRecords = 0;
        int totalDuplicates = 0;
        int totalErrors = 0;
        
        List<Map<String, Object>> deviceResults = new ArrayList<>();
        
        for (BiometricDevice device : devices) {
            logger.info("Iniciando sincronización de " + device.id);
            SyncStats stats = syncBiometricData(device);
            
            Map<String, Object> deviceResult = new HashMap<>();
            deviceResult.put("deviceId", device.id);
            deviceResult.put("ip", device.ip);
            deviceResult.put("stats", stats.toMap());
            deviceResults.add(deviceResult);
            
            totalRecords += stats.totalRecords;
            totalNewRecords += stats.newRecords;
            totalDuplicates += stats.duplicates;
            totalErrors += stats.errors;
        }
        
        globalStats.put("totalRecords", totalRecords);
        globalStats.put("newRecords", totalNewRecords);
        globalStats.put("duplicates", totalDuplicates);
        globalStats.put("errors", totalErrors);
        globalStats.put("deviceResults", deviceResults);
        globalStats.put("timestamp", LocalDateTime.now().format(DATE_TIME_FORMATTER));
        
        return globalStats;
    }
}