# Proxmox Timezone Sync Script 🕒

This script allows you to **easily set the timezone** on all **Proxmox nodes** and their **LXC containers**.  
It provides a **beautifully formatted timezone selection menu**, auto-detects other nodes, and installs missing dependencies like `jq`.

## 🚀 Features
✅ **Dynamically lists all available timezones**  
✅ **User-friendly selection menu** with columns and pagination  
✅ **Automatically installs `jq` on all nodes** if missing  
✅ **Uses IP instead of hostname for SSH** to avoid resolution issues  
✅ **Works on a single node or multiple Proxmox cluster nodes**  
✅ **Allows selecting ALL containers or specific ones**  
✅ **Runs only on the local node if no cluster is found**  

---

## 📌 Installation

1. **Download the script**
   ```bash
   wget https://raw.githubusercontent.com/justmurty/timezone_proxmox/refs/heads/main/timezone.sh
