<%@ page import="java.sql.*, com.asistenciav2.util.DatabaseConnection" %>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<html>
<head><title>Test Permissions</title></head>
<body>
<h2>Testing Database Connection and Permissions</h2>
<%
try {
    // Test database connection
    Connection conn = DatabaseConnection.getConnection();
    out.println("<p>✓ Database connection successful</p>");
    
    // Test permission types
    Statement stmt = conn.createStatement();
    ResultSet rs = stmt.executeQuery("SELECT id, codigo, descripcion FROM permissiontypes WHERE estado = 1");
    out.println("<h3>Available Permission Types:</h3>");
    out.println("<table border='1'><tr><th>ID</th><th>Code</th><th>Description</th></tr>");
    while (rs.next()) {
        out.println("<tr>");
        out.println("<td>" + rs.getInt("id") + "</td>");
        out.println("<td>" + rs.getString("codigo") + "</td>");
        out.println("<td>" + rs.getString("descripcion") + "</td>");
        out.println("</tr>");
    }
    out.println("</table>");
    
    // Test users
    rs = stmt.executeQuery("SELECT id, dni, nombre, apellidos FROM users WHERE estado = 1 LIMIT 5");
    out.println("<h3>Available Users:</h3>");
    out.println("<table border='1'><tr><th>ID</th><th>DNI</th><th>Name</th><th>Last Name</th></tr>");
    while (rs.next()) {
        out.println("<tr>");
        out.println("<td>" + rs.getInt("id") + "</td>");
        out.println("<td>" + rs.getString("dni") + "</td>");
        out.println("<td>" + rs.getString("nombre") + "</td>");
        out.println("<td>" + rs.getString("apellidos") + "</td>");
        out.println("</tr>");
    }
    out.println("</table>");
    
    // Test permissions table structure
    DatabaseMetaData meta = conn.getMetaData();
    rs = meta.getColumns(null, null, "permissions", null);
    out.println("<h3>Permissions Table Structure:</h3>");
    out.println("<table border='1'><tr><th>Column</th><th>Type</th><th>Nullable</th></tr>");
    while (rs.next()) {
        out.println("<tr>");
        out.println("<td>" + rs.getString("COLUMN_NAME") + "</td>");
        out.println("<td>" + rs.getString("TYPE_NAME") + "</td>");
        out.println("<td>" + (rs.getBoolean("NULLABLE") ? "YES" : "NO") + "</td>");
        out.println("</tr>");
    }
    out.println("</table>");
    
    conn.close();
} catch (Exception e) {
    out.println("<p style='color:red'>✗ Error: " + e.getMessage() + "</p>");
    e.printStackTrace(new java.io.PrintWriter(out));
}
%>
</body>
</html>