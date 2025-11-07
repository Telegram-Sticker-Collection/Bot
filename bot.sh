#!/bin/bash

# for debug
# set -x

ADMIN_CHAT_IDS=("$ADMIN_CHAT_ID")

STICKER_DIR="./stickers"
STICKER_INFO_DIR="$STICKER_DIR/info"
STICKER_FILES_DIR="$STICKER_DIR/files"

initialize_directory() {
    mkdir -p "$STICKER_INFO_DIR"
    mkdir -p "$STICKER_FILES_DIR"
}

# update_index() {
#     thumbnails=$(cat "$STICKER_DIR/thumbnails.json")
# }

# Function to check if the sticker set info exists and if it needs to be updated
needs_update() {
    local set_name="$1"
    local info_file="$STICKER_INFO_DIR/$set_name.json"

    if [[ -f "$info_file" ]]; then
        last_sticker_info_download_timestamp=$(jq -r '.last_sticker_info_download' "$info_file")
        current_timestamp=$(date +%s)
        
        # Check if last download was over 15 days ago
        if (( (current_timestamp - last_sticker_info_download_timestamp) < 1296000 )); then
            return 1  # No update needed
        fi
    fi
    
    return 0  # Update needed
}

send_message() {
    local text="$1"
    local chat_id="$2"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$chat_id&text=$text"
}

download_sticker_set_info() {
    local set_name="$1"
    response=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getStickerSet?name=$set_name")

    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
        echo "$response" | jq '.result + {last_sticker_info_download: now | floor}' > "$STICKER_INFO_DIR/$set_name.json"
        return 0
    else
        echo "Error: $(echo "$response" | jq -r .description)"
        return 1
    fi
}

download_file() {
    local url="$1"
    local file_name="$2"

    curl -s -o "$file_name" "$url"
}

handle_sticker() {
    local sticker_set_name="$1"
    local $chat_id="$2" # requester user

    if ! needs_update "$sticker_set_name"; then
        echo "Sticker set '$sticker_set_name' is already downloaded or updated recently."
        return
    fi

    # Download the sticker set information
    if ! download_sticker_set_info "$sticker_set_name"; then
        return
    fi

    send_message "Got sticker set info for '$sticker_set_name'" "$chat_id"
    
    # Create a directory for the sticker set
    mkdir -p "$STICKER_FILES_DIR/$sticker_set_name"

    # Read sticker set info from JSON file
    set_info=$(cat "$STICKER_INFO_DIR/$sticker_set_name.json")
    stickers=$(echo "$set_info" | jq -c '.stickers[]')

    # Download each sticker
    for sticker in $stickers; do
        file_id=$(echo "$sticker" | jq -r '.file_id')
        file_unique_id=$(echo "$sticker" | jq -r '.file_unique_id')
        file_path=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getFile?file_id=$file_id" | jq -r '.result.file_path')
        extension="${file_path##*.}"
        set_info=$(echo "$set_info" | jq --arg unique_id "$file_unique_id" --arg ext "$extension" '.stickers |= map(if .file_unique_id == $unique_id then . + {extension: $ext} else . end)')
        download_file "https://api.telegram.org/file/bot$BOT_TOKEN/$file_path" "$STICKER_FILES_DIR/$sticker_set_name/$file_unique_id.$extension"
    done

    # Download the thumbnail if it exists
    # thumb_file_id=$(echo "$set_info" | jq -r 'if .thumbnail.file_id then .thumbnail.file_id 
    #                   elif .stickers[0].thumbnail.file_id then .stickers[0].thumbnail.file_id  # <--- this may be not tgs for animated packs
    #                   else .stickers[0].file_id end')
    thumb_file_id=$(echo "$set_info" | jq -r 'if .thumbnail.file_id then .thumbnail.file_id 
                    else .stickers[0].file_id end')
    if [[ "$thumb_file_id" != "null" ]]; then
        file_path=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getFile?file_id=$thumb_file_id" | jq -r '.result.file_path')
        extension="${file_path##*.}"
        set_info=$(echo "$set_info" | jq --arg ext "$extension" '. + {thumbnail_extension: $ext}')
        download_file "https://api.telegram.org/file/bot$BOT_TOKEN/$file_path" "$STICKER_FILES_DIR/$sticker_set_name/thumbnail.$extension"
    fi

    # Update last download timestamp
    set_info=$(echo "$set_info" | jq '. + {last_file_download: now | floor}')

    echo "$set_info" > "$STICKER_INFO_DIR/$sticker_set_name.json"

    send_message "Downloaded all stickers for set '$sticker_set_name'" "$chat_id"
}

start_bot() {
    echo "bot started"

    # Bot update loop
    offset=0
    while true; do
        response=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$offset")
        offset=$(echo "$response" | jq '.result | map(.update_id) | max + 1')

        # Iterate over each update in the response
        echo "$response" | jq -c '.result[]' | while read -r update; do
            chat_id=$(echo "$update" | jq -r '.message.chat.id // empty')

            if [[ "${ADMIN_CHAT_IDS[@]}" =~ "$chat_id" ]]; then
                # Check for sticker
                sticker_set_name=$(echo "$update" | jq -r '.message.sticker.set_name // empty')
                if [[ -n "$sticker_set_name" ]]; then
                    send_message "Sticker set received: '$sticker_set_name'" "$chat_id"
                    handle_sticker "$sticker_set_name" "$chat_id"
                fi
            fi
        done
        sleep 1
    done
}

main() {
    initialize_directory
    start_bot
}

main
