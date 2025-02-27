#!/bin/bash

# Function to select a timezone dynamically
select_timezone() {
    echo "🌍 Retrieving available timezones..."
    
    # Get all available timezones
    TIMEZONES=($(timedatectl list-timezones))

    # Determine terminal width for better column display
    TERM_WIDTH=$(tput cols)
    COLUMNS=4  # Default to 4 columns

    if [[ "$TERM_WIDTH" -lt 80 ]]; then
        COLUMNS=2  # If terminal is narrow, use 2 columns
    elif [[ "$TERM_WIDTH" -gt 120 ]]; then
        COLUMNS=5  # If terminal is wide, use 5 columns
    fi

    # Paginate the timezones to avoid an overwhelming list
    PAGE_SIZE=100  # Number of timezones per page
    TOTAL_PAGES=$(( (${#TIMEZONES[@]} + PAGE_SIZE - 1) / PAGE_SIZE ))  # Calculate total pages
    PAGE=1

    while true; do
        clear
        echo "🌍 Select the timezone you want to apply (Page $PAGE of $TOTAL_PAGES):"

        # Calculate start and end index for pagination
        START_INDEX=$(( (PAGE - 1) * PAGE_SIZE ))
        END_INDEX=$(( START_INDEX + PAGE_SIZE ))
        if [[ "$END_INDEX" -gt "${#TIMEZONES[@]}" ]]; then
            END_INDEX="${#TIMEZONES[@]}"
        fi

        # Format output into columns
        TZ_DISPLAY=()
        for ((i = START_INDEX; i < END_INDEX; i++)); do
            TZ_DISPLAY+=("$((i+1)). ${TIMEZONES[$i]}")
        done
        printf "%s\n" "${TZ_DISPLAY[@]}" | column -c $((TERM_WIDTH - 5))

        echo -e "\n(N) Next Page | (P) Previous Page | (Q) Quit"
        read -p "Enter the number of your choice: " TZ_INDEX

        # Navigation options
        case "$TZ_INDEX" in
            [nN]) ((PAGE < TOTAL_PAGES)) && ((PAGE++)) ;;
            [pP]) ((PAGE > 1)) && ((PAGE--)) ;;
            [qQ]) echo "❌ Timezone selection canceled."; exit 1 ;;
            *)
                if [[ "$TZ_INDEX" =~ ^[0-9]+$ ]] && [ "$TZ_INDEX" -le "${#TIMEZONES[@]}" ]; then
                    TIMEZONE="${TIMEZONES[$((TZ_INDEX-1))]}"
                    echo "✅ Timezone selected: $TIMEZONE"
                    break
                else
                    echo "❌ Invalid choice. Please enter a valid number."
                fi
                ;;
        esac
    done
}

# Function to check and install jq on a node
install_jq_if_missing() {
    NODE_IP=$1
    echo "🔍 Checking if 'jq' is installed on node ($NODE_IP)..."
    if ! ssh root@$NODE_IP "command -v jq >/dev/null 2>&1"; then
        echo "⚠️ 'jq' is missing on $NODE_IP. Installing..."
        ssh root@$NODE_IP "apt update && apt install -y jq"
        echo "✅ 'jq' installed on $NODE_IP!"
    else
        echo "✅ 'jq' is already installed on $NODE_IP."
    fi
}

# Function to retrieve a node's IP from Proxmox API
get_node_ip() {
    NODE_NAME=$1
    NODE_IP=$(pvesh get /nodes/$NODE_NAME/network --output-format=json | jq -r '.[] | select(.iface=="vmbr0") | .address')

    if [[ -z "$NODE_IP" ]]; then
        echo "❌ Unable to determine IP for node: $NODE_NAME. Skipping..."
    fi

    echo "$NODE_IP"
}

# Function to change the timezone on a Proxmox node and its LXC containers
change_timezone_on_node() {
    NODE_NAME=$1
    NODE_IP=$(get_node_ip $NODE_NAME)

    if [[ -z "$NODE_IP" ]]; then
        return
    fi

    # Ensure jq is installed
    install_jq_if_missing "$NODE_IP"

    echo "🔹 Processing node: $NODE_NAME ($NODE_IP)"

    # If this is the current node
    if [ "$NODE_NAME" == "$(hostname)" ]; then
        echo "🔧 Setting timezone on local Proxmox node ($NODE_NAME)..."
        timedatectl set-timezone $TIMEZONE
    else
        echo "🖥️ Connecting to $NODE_NAME via IP ($NODE_IP) to update timezone..."
        ssh root@$NODE_IP "timedatectl set-timezone $TIMEZONE"
    fi
    echo "✅ Timezone on $NODE_NAME updated!"

    echo "📦 Fetching container list from $NODE_NAME..."
    CONTAINERS=$(ssh root@$NODE_IP "pct list | awk 'NR>1 {print \$1,\$3}'")

    if [[ -z "$CONTAINERS" ]]; then
        echo "❌ No containers found on $NODE_NAME!"
        return
    fi

    echo "📋 Available containers on $NODE_NAME:"
    echo "$CONTAINERS" | awk '{print "ID: "$1", Hostname: "$2}'

    # Ask user if they want to update all containers or select specific ones
    echo "👉 Do you want to update the timezone for ALL containers? (yes/no)"
    read -r ALL_CONTAINERS

    if [[ "$ALL_CONTAINERS" == "yes" ]]; then
        SELECTED_CONTAINERS=$(echo "$CONTAINERS" | awk '{print $1}')
    else
        echo "📝 Enter container IDs separated by space (e.g., 101 102 105):"
        read -r SELECTED_CONTAINERS
    fi

    # Update timezone for selected containers
    for CTID in $SELECTED_CONTAINERS; do
        echo "➡️  Updating timezone for container $CTID on $NODE_NAME..."
        
        # Execute commands inside the container
        ssh root@$NODE_IP "pct exec $CTID -- ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
        ssh root@$NODE_IP "pct exec $CTID -- echo \"$TIMEZONE\" > /etc/timezone"
        ssh root@$NODE_IP "pct exec $CTID -- dpkg-reconfigure -f noninteractive tzdata"
        
        echo "✅ Timezone for container $CTID on $NODE_NAME updated!"
    done
}

# Start script execution
echo "⏳ Starting timezone update for all Proxmox nodes and their containers..."

# Select timezone
select_timezone

# Fetch all Proxmox nodes in the cluster
echo "🔍 Fetching Proxmox cluster nodes..."
NODES=$(pvesh get /cluster/status --output-format=json | jq -r '.[] | select(.type=="node") | .name')

# Count nodes in the cluster
NODE_COUNT=$(echo "$NODES" | wc -l)

# If there's only one node, run on this node only
if [[ "$NODE_COUNT" -eq 1 ]]; then
    echo "⚠️ Only one Proxmox node detected. Updating this node only."
    change_timezone_on_node "$(hostname)"
else
    # Run the script for all nodes
    for NODE in $NODES; do
        change_timezone_on_node $NODE
    done
fi

echo "🎉 Timezone update completed for all selected nodes and containers!"
