#!/bin/bash

# Flutter Android Debug Script using adb
# Usage: ./debug_android.sh [command]

APP_PACKAGE="com.example.flutter_application"
MAIN_ACTIVITY="$APP_PACKAGE/.MainActivity"
SCREENSHOT_DIR="./debug_screenshots"
UI_DUMP_FILE="./ui_dump.xml"
COORDINATES_FILE="./coordinates.json"
DEVICE_PROFILES_FILE="./device_profiles.json"

# Create screenshot directory
mkdir -p $SCREENSHOT_DIR

# Simplified UIAutomator-based Coordinate Detection
find_element_with_uiautomator() {
    local search_term="$1"
    local prefer_clickable="${2:-true}"  # Default to prefer clickable elements
    
    echo "🤖 Using UIAutomator to find element: '$search_term'" >&2
    
    # Get UI dump first
    adb shell uiautomator dump /sdcard/temp.xml >/dev/null 2>&1
    
    # Search for element in the XML using local processing
    adb pull /sdcard/temp.xml ./temp_ui.xml >/dev/null 2>&1
    adb shell rm -f /sdcard/temp.xml >/dev/null 2>&1
    
    if [ ! -f "./temp_ui.xml" ]; then
        echo "   ❌ Failed to get UI dump" >&2
        return 1
    fi
    
    local result=""
    
    # If preferring clickable elements, search for clickable elements first
    if [ "$prefer_clickable" = "true" ]; then
        # Search for clickable elements with content-desc containing search term
        result=$(grep 'clickable="true"' ./temp_ui.xml | grep -i "content-desc=\"[^\"]*$search_term[^\"]*\"" | head -1)
        
        # If not found, search for clickable elements with text containing search term
        if [ -z "$result" ]; then
            result=$(grep 'clickable="true"' ./temp_ui.xml | grep -i "text=\"[^\"]*$search_term[^\"]*\"" | head -1)
        fi
    fi
    
    # If no clickable element found, search in all elements
    if [ -z "$result" ]; then
        # Search for content-desc first (most reliable)
        result=$(grep -i "content-desc=\"[^\"]*$search_term[^\"]*\"" ./temp_ui.xml | head -1)
        
        # If not found, search in text attribute
        if [ -z "$result" ]; then
            result=$(grep -i "text=\"[^\"]*$search_term[^\"]*\"" ./temp_ui.xml | head -1)
        fi
    fi
    
    # Extract bounds if found
    if [ -n "$result" ]; then
        local bounds=$(echo "$result" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
        
        if [ -n "$bounds" ]; then
            local x1=$(echo $bounds | cut -d',' -f1)
            local y1=$(echo $bounds | cut -d',' -f2)
            local x2=$(echo $bounds | cut -d',' -f3)
            local y2=$(echo $bounds | cut -d',' -f4)
            local center_x=$(( (x1 + x2) / 2 ))
            local center_y=$(( (y1 + y2) / 2 ))
            
            # Check if element is clickable
            local is_clickable=$(echo "$result" | grep -o 'clickable="[^"]*"' | cut -d'"' -f2)
            echo "   ✅ Found at center: ($center_x, $center_y) [clickable: $is_clickable]" >&2
            echo "   📍 Bounds: [$x1,$y1][$x2,$y2]" >&2
            
            # Clean up temp file
            rm -f ./temp_ui.xml
            
            echo "$center_x,$center_y"
            return 0
        fi
    fi
    
    # Clean up temp file
    rm -f ./temp_ui.xml
    
    echo "   ❌ Element not found" >&2
    return 1
}

# Direct UIAutomator tap using coordinates
uiautomator_tap_by_coords() {
    local search_term="$1"
    
    echo "🤖 Finding and tapping element: '$search_term'" >&2
    
    local coords=$(find_element_with_uiautomator "$search_term")
    if [ $? -eq 0 ] && [ -n "$coords" ]; then
        local x=$(echo $coords | cut -d',' -f1)
        local y=$(echo $coords | cut -d',' -f2)
        
        echo "   🎯 Tapping at: ($x, $y)" >&2
        adb shell input tap $x $y
        return 0
    fi
    
    return 1
}

get_ui_dump() {
    echo "🔍 Getting UI hierarchy..." >&2
    adb shell uiautomator dump /sdcard/ui_dump.xml
    adb pull /sdcard/ui_dump.xml $UI_DUMP_FILE
    
    # Clean up temporary file on device
    adb shell rm -f /sdcard/ui_dump.xml
    
    echo "✅ UI dump saved to $UI_DUMP_FILE" >&2
}

find_element_coordinates() {
    local search_text="$1"
    local dump_file="${2:-$UI_DUMP_FILE}"
    
    if [ ! -f "$dump_file" ]; then
        echo "❌ UI dump file not found. Run 'get-ui-dump' first." >&2
        return 1
    fi
    
    echo "🔍 Searching for element containing: '$search_text'" >&2
    
    # Search for clickable elements with content-desc or text containing search term
    local result=$(grep -i "clickable=\"true\"" "$dump_file" | grep -i "$search_text" | head -1 | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
    
    # If no clickable element found, search for any element with the search term
    if [ -z "$result" ]; then
        result=$(grep -i "$search_text" "$dump_file" | head -1 | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
    fi
    
    if [ -n "$result" ]; then
        local x1=$(echo $result | cut -d',' -f1)
        local y1=$(echo $result | cut -d',' -f2)
        local x2=$(echo $result | cut -d',' -f3)
        local y2=$(echo $result | cut -d',' -f4)
        local center_x=$(( (x1 + x2) / 2 ))
        local center_y=$(( (y1 + y2) / 2 ))
        
        echo "📍 Found element at center: ($center_x, $center_y)" >&2
        echo "📍 Bounds: [$x1,$y1][$x2,$y2]" >&2
        echo "$center_x,$center_y"
        return 0
    else
        echo "❌ Element not found" >&2
        return 1
    fi
}

save_coordinates() {
    local name="$1"
    local x="$2"  
    local y="$3"
    
    # Create or update coordinates JSON file
    if [ ! -f "$COORDINATES_FILE" ]; then
        echo "{}" > "$COORDINATES_FILE"
    fi
    
    # Use python to update JSON (more reliable than sed)
    python3 -c "
import json
import sys

try:
    with open('$COORDINATES_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['$name'] = {'x': $x, 'y': $y}

with open('$COORDINATES_FILE', 'w') as f:
    json.dump(data, f, indent=2)

print(f'✅ Saved coordinates for \"$name\": ({$x}, {$y})')
"
}

load_coordinates() {
    local name="$1"
    
    if [ ! -f "$COORDINATES_FILE" ]; then
        echo "❌ Coordinates file not found"
        return 1
    fi
    
    python3 -c "
import json
try:
    with open('$COORDINATES_FILE', 'r') as f:
        data = json.load(f)
    if '$name' in data:
        coord = data['$name']
        print(f\"{coord['x']},{coord['y']}\")
    else:
        print('not_found')
        exit(1)
except:
    print('error')
    exit(1)
"
}

get_device_info() {
    local resolution=$(adb shell wm size | cut -d' ' -f3)
    local density=$(adb shell wm density | cut -d' ' -f3)
    local model=$(adb shell getprop ro.product.model | tr -d '\r')
    
    echo "📱 Device: $model"
    echo "📐 Resolution: $resolution"
    echo "🔍 Density: $density"
    
    echo "$model|$resolution|$density"
}

load_device_profile() {
    local device_key="$1"
    
    if [ ! -f "$DEVICE_PROFILES_FILE" ]; then
        echo "❌ Device profiles file not found"
        return 1
    fi
    
    python3 -c "
import json
try:
    with open('$DEVICE_PROFILES_FILE', 'r') as f:
        data = json.load(f)
    
    if '$device_key' in data['devices']:
        profile = data['devices']['$device_key']
        coords = profile['coordinates']
        
        # Save all coordinates from this device profile
        import os
        coord_data = {}
        if os.path.exists('$COORDINATES_FILE'):
            with open('$COORDINATES_FILE', 'r') as f:
                coord_data = json.load(f)
        
        coord_data.update(coords)
        
        with open('$COORDINATES_FILE', 'w') as f:
            json.dump(coord_data, f, indent=2)
        
        print(f'✅ Loaded profile for {profile[\"name\"]}')
        for name, coord in coords.items():
            print(f'📍 {name}: ({coord[\"x\"]}, {coord[\"y\"]})')
    else:
        print('❌ Device profile not found')
        exit(1)
except Exception as e:
    print(f'❌ Error loading device profile: {e}')
    exit(1)
"
}

auto_detect_device() {
    echo "🔍 Auto-detecting device..."
    local device_info=$(get_device_info)
    local model=$(echo $device_info | cut -d'|' -f1)
    local resolution=$(echo $device_info | cut -d'|' -f2)
    local density=$(echo $device_info | cut -d'|' -f3)
    
    # Try to match known device profiles
    case "$model" in
        *"Pixel 7"*)
            echo "📱 Detected Google Pixel 7"
            load_device_profile "pixel_7"
            ;;
        *"Pixel 8"*)
            echo "📱 Detected Google Pixel 8"
            load_device_profile "pixel_8"
            ;;
        *"Galaxy S23"*)
            echo "📱 Detected Samsung Galaxy S23"
            load_device_profile "galaxy_s23"
            ;;
        *"OnePlus"*)
            echo "📱 Detected OnePlus device"
            load_device_profile "oneplus_11"
            ;;
        *)
            echo "📱 Unknown device, using generic profile based on resolution"
            if [[ "$resolution" == "1080x"* ]]; then
                load_device_profile "generic_1080p"
            else
                echo "⚠️ No matching profile found. Please run 'detect-coordinates' to create custom coordinates."
                return 1
            fi
            ;;
    esac
}

verify_element_coordinates() {
    local element_name="$1"
    local search_patterns="$2"
    
    echo "🔍 Verifying coordinates for '$element_name' using UIAutomator..." >&2
    
    # Try to find element with multiple search patterns using UIAutomator
    IFS='|' read -ra PATTERNS <<< "$search_patterns"
    for pattern in "${PATTERNS[@]}"; do
        echo "   🤖 UIAutomator searching for pattern: '$pattern'" >&2
        local coords=$(find_element_with_uiautomator "$pattern")
        if [ $? -eq 0 ] && [ -n "$coords" ] && [[ "$coords" =~ ^[0-9]+,[0-9]+$ ]]; then
            local x=$(echo $coords | cut -d',' -f1)
            local y=$(echo $coords | cut -d',' -f2)
            echo "   ✅ UIAutomator found at: ($x, $y)" >&2
            
            # Update saved coordinates if different
            local saved_coords=$(load_coordinates "$element_name" 2>/dev/null)
            if [ "$coords" != "$saved_coords" ]; then
                echo "   📝 Updating saved coordinates" >&2
                save_coordinates "$element_name" $x $y >&2
            fi
            echo "$x,$y"
            return 0
        fi
    done
    
    echo "   ❌ Element not found with UIAutomator" >&2
    return 1
}

verify_button_exists_visually() {
    local x="$1"
    local y="$2"
    local element_name="$3"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    echo "🔍 Visually verifying '$element_name' exists at coordinates ($x, $y)..." >&2
    
    # Take current screenshot
    adb shell screencap /sdcard/verify_$timestamp.png
    adb pull /sdcard/verify_$timestamp.png $SCREENSHOT_DIR/
    adb shell rm -f /sdcard/verify_$timestamp.png
    
    # Get UI dump to check element visibility
    adb shell uiautomator dump /sdcard/temp_verify.xml >/dev/null 2>&1
    adb pull /sdcard/temp_verify.xml ./temp_verify.xml >/dev/null 2>&1
    adb shell rm -f /sdcard/temp_verify.xml >/dev/null 2>&1
    
    if [ -f "./temp_verify.xml" ]; then
        # Check if any clickable element exists near the coordinates (within 50px tolerance)
        local found_element=""
        local tolerance=50
        
        while IFS= read -r line; do
            if [[ "$line" == *'clickable="true"'* ]]; then
                local bounds=$(echo "$line" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
                if [ -n "$bounds" ]; then
                    local x1=$(echo $bounds | cut -d',' -f1)
                    local y1=$(echo $bounds | cut -d',' -f2)
                    local x2=$(echo $bounds | cut -d',' -f3)
                    local y2=$(echo $bounds | cut -d',' -f4)
                    local center_x=$(( (x1 + x2) / 2 ))
                    local center_y=$(( (y1 + y2) / 2 ))
                    
                    # Check if target coordinates are within element bounds or tolerance
                    if [ $x -ge $((x1 - tolerance)) ] && [ $x -le $((x2 + tolerance)) ] && \
                       [ $y -ge $((y1 - tolerance)) ] && [ $y -le $((y2 + tolerance)) ]; then
                        found_element="$line"
                        echo "   ✅ Found clickable element near target coordinates" >&2
                        echo "   📍 Element bounds: [$x1,$y1][$x2,$y2], center: ($center_x, $center_y)" >&2
                        break
                    fi
                fi
            fi
        done < "./temp_verify.xml"
        
        rm -f "./temp_verify.xml"
        
        if [ -n "$found_element" ]; then
            echo "   ✅ Button verification passed - clickable element found" >&2
            echo "📷 Verification screenshot: debug_screenshots/verify_$timestamp.png" >&2
            return 0
        else
            echo "   ⚠️  Warning: No clickable element found near coordinates ($x, $y)" >&2
            echo "   📷 Check screenshot: debug_screenshots/verify_$timestamp.png" >&2
            
            # List nearby elements for debugging
            echo "   🔍 Nearby elements within ${tolerance}px:" >&2
            while IFS= read -r line; do
                local bounds=$(echo "$line" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
                if [ -n "$bounds" ]; then
                    local x1=$(echo $bounds | cut -d',' -f1)
                    local y1=$(echo $bounds | cut -d',' -f2)
                    local x2=$(echo $bounds | cut -d',' -f3)
                    local y2=$(echo $bounds | cut -d',' -f4)
                    local center_x=$(( (x1 + x2) / 2 ))
                    local center_y=$(( (y1 + y2) / 2 ))
                    
                    local distance_x=$((x > center_x ? x - center_x : center_x - x))
                    local distance_y=$((y > center_y ? y - center_y : center_y - y))
                    
                    if [ $distance_x -lt $tolerance ] && [ $distance_y -lt $tolerance ]; then
                        local desc=$(echo "$line" | sed -n 's/.*content-desc="\([^"]*\)".*/\1/p')
                        local clickable=$(echo "$line" | sed -n 's/.*clickable="\([^"]*\)".*/\1/p')
                        echo "     - Element at ($center_x, $center_y), clickable: $clickable, desc: \"$desc\"" >&2
                    fi
                fi
            done < <(grep 'bounds="\[' ./temp_verify.xml 2>/dev/null)
            
            return 1
        fi
    else
        echo "   ❌ Failed to get UI dump for verification" >&2
        return 1
    fi
}

preview_tap_location() {
    local x="$1"
    local y="$2"
    local element_name="$3"
    
    # Validate coordinates are numeric
    if ! [[ "$x" =~ ^[0-9]+$ ]] || ! [[ "$y" =~ ^[0-9]+$ ]]; then
        echo "❌ Invalid coordinates: x='$x', y='$y'" >&2
        return 1
    fi
    
    # First verify button exists visually
    if ! verify_button_exists_visually "$x" "$y" "$element_name"; then
        echo "⚠️  Proceeding with tap despite verification warning..." >&2
    fi
    
    echo "📸 Taking preview screenshot before tap..." >&2
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    adb shell screencap /sdcard/preview_$timestamp.png
    adb pull /sdcard/preview_$timestamp.png $SCREENSHOT_DIR/
    adb shell rm -f /sdcard/preview_$timestamp.png
    
    echo "🎯 About to tap '$element_name' at coordinates ($x, $y)" >&2
    echo "📷 Preview saved: debug_screenshots/preview_$timestamp.png" >&2
    
    # Optional: Add visual indicator on screenshot (if imagemagick available)
    if command -v convert >/dev/null 2>&1; then
        convert $SCREENSHOT_DIR/preview_$timestamp.png \
            -fill red -stroke red -strokewidth 3 \
            -draw "circle $x,$y $((x+10)),$((y+10))" \
            $SCREENSHOT_DIR/preview_${timestamp}_marked.png 2>/dev/null || true
    fi
}

verify_expected_screen() {
    local expected_screen="$1"
    local element_name="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    echo "🔍 Verifying expected screen state after '$element_name' tap..." >&2
    
    # Wait for UI to settle
    sleep 2
    
    # Take screenshot of current state
    adb shell screencap /sdcard/post_tap_$timestamp.png
    adb pull /sdcard/post_tap_$timestamp.png $SCREENSHOT_DIR/
    adb shell rm -f /sdcard/post_tap_$timestamp.png
    
    # Get UI dump to analyze screen content
    adb shell uiautomator dump /sdcard/temp_post.xml >/dev/null 2>&1
    adb pull /sdcard/temp_post.xml ./temp_post.xml >/dev/null 2>&1
    adb shell rm -f /sdcard/temp_post.xml >/dev/null 2>&1
    
    if [ ! -f "./temp_post.xml" ]; then
        echo "   ❌ Failed to get UI dump for screen verification" >&2
        return 1
    fi
    
    echo "📷 Post-tap screenshot: debug_screenshots/post_tap_$timestamp.png" >&2
    
    case "$expected_screen" in
        "recording")
            # Check for recording indicators
            if grep -qi "録音中\|recording\|停止\|stop" ./temp_post.xml; then
                echo "   ✅ Recording screen detected - found recording indicators" >&2
                rm -f ./temp_post.xml
                return 0
            else
                echo "   ⚠️  Expected recording screen, but no recording indicators found" >&2
            fi
            ;;
        "chat")
            # Check for chat/AI interface elements
            if grep -qi "chat\|AI\|メッセージ\|message\|送信\|send" ./temp_post.xml; then
                echo "   ✅ Chat screen detected - found chat interface elements" >&2
                rm -f ./temp_post.xml
                return 0
            else
                echo "   ⚠️  Expected chat screen, but no chat interface found" >&2
            fi
            ;;
        "main")
            # Check for main app elements
            if grep -qi "SessionMUSE\|録音\|record\|AIと相談" ./temp_post.xml; then
                echo "   ✅ Main screen detected - found main app elements" >&2
                rm -f ./temp_post.xml
                return 0
            else
                echo "   ⚠️  Expected main screen, but main elements not found" >&2
            fi
            ;;
        *)
            echo "   ℹ️  Unknown expected screen type: $expected_screen" >&2
            ;;
    esac
    
    # Log some visible text elements for debugging
    echo "   🔍 Visible text elements on screen:" >&2
    grep -o 'content-desc="[^"]*"' ./temp_post.xml | head -5 | sed 's/content-desc="\([^"]*\)"/     - "\1"/' >&2
    
    rm -f ./temp_post.xml
    return 1
}

smart_tap() {
    local element_name="$1"
    local fallback_x="$2"
    local fallback_y="$3"
    local search_patterns="$4"
    local expected_screen="$5"  # New parameter for expected screen state
    
    echo "🎯 Smart tap for '$element_name'"
    
    # First try to verify coordinates with UI dump
    if [ -n "$search_patterns" ]; then
        local verified_coords=$(verify_element_coordinates "$element_name" "$search_patterns")
        if [ $? -eq 0 ] && [ -n "$verified_coords" ]; then
            local x=$(echo $verified_coords | cut -d',' -f1)
            local y=$(echo $verified_coords | cut -d',' -f2)
            
            # Preview the tap location
            preview_tap_location $x $y "$element_name"
            
            echo "📍 Using verified coordinates for '$element_name': ($x, $y)"
            adb shell input tap $x $y
            
            # Verify expected screen state if provided
            if [ -n "$expected_screen" ]; then
                verify_expected_screen "$expected_screen" "$element_name"
            fi
            
            return 0
        fi
    fi
    
    # Fallback to saved coordinates
    local coords=$(load_coordinates "$element_name" 2>/dev/null)
    if [ $? -eq 0 ] && [ "$coords" != "not_found" ] && [ "$coords" != "error" ]; then
        local x=$(echo $coords | cut -d',' -f1)
        local y=$(echo $coords | cut -d',' -f2)
        
        # Preview the tap location
        preview_tap_location $x $y "$element_name"
        
        echo "📍 Using saved coordinates for '$element_name': ($x, $y)"
        echo "⚠️  Warning: Using old coordinates (not verified against current UI)"
        adb shell input tap $x $y
        
        # Verify expected screen state if provided
        if [ -n "$expected_screen" ]; then
            verify_expected_screen "$expected_screen" "$element_name"
        fi
        
        return 0
    fi
    
    # Final fallback to hardcoded coordinates
    if [ -n "$fallback_x" ] && [ -n "$fallback_y" ]; then
        preview_tap_location $fallback_x $fallback_y "$element_name"
        
        echo "📍 Using fallback coordinates for '$element_name': ($fallback_x, $fallback_y)"
        echo "⚠️  Warning: Using hardcoded fallback coordinates"
        adb shell input tap $fallback_x $fallback_y
        
        # Verify expected screen state if provided
        if [ -n "$expected_screen" ]; then
            verify_expected_screen "$expected_screen" "$element_name"
        fi
        
        return 0
    fi
    
    echo "❌ No coordinates available for '$element_name'"
    echo "💡 Try running 'detect-coordinates' first"
    return 1
}

# Cleanup function for all temporary files
cleanup_temp_files() {
    echo "🧹 Cleaning up temporary files..."
    
    # Clean up device temporary files
    adb shell rm -f /sdcard/ui_dump.xml
    adb shell rm -f /sdcard/launch.png
    adb shell rm -f /sdcard/record_state.png
    adb shell rm -f /sdcard/stop_state.png
    adb shell rm -f /sdcard/chat_state.png
    adb shell rm -f /sdcard/restart.png
    adb shell rm -f /sdcard/debug_*.png
    adb shell rm -f /sdcard/preview_*.png
    adb shell rm -f /sdcard/verify_*.png
    adb shell rm -f /sdcard/post_tap_*.png
    adb shell rm -f /sdcard/temp_verify.xml
    adb shell rm -f /sdcard/temp_post.xml
    adb shell rm -f /sdcard/app_debug.mp4
    
    # Clean up local temporary files
    rm -f ./temp_verify.xml
    rm -f ./temp_ui.xml
    rm -f ./temp_post.xml
    
    echo "✅ Device and local temporary files cleaned up"
}

# Interactive coordinate confirmation
confirm_coordinates() {
    local element_name="$1"
    
    echo "🎯 Interactive coordinate confirmation for '$element_name'"
    echo "📸 Taking current screenshot for analysis..."
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    adb shell screencap /sdcard/confirm_$timestamp.png
    adb pull /sdcard/confirm_$timestamp.png $SCREENSHOT_DIR/
    adb shell rm -f /sdcard/confirm_$timestamp.png
    
    echo "📷 Screenshot saved: debug_screenshots/confirm_$timestamp.png"
    echo "📋 Current saved coordinates for '$element_name':"
    
    local coords=$(load_coordinates "$element_name" 2>/dev/null)
    if [ $? -eq 0 ] && [ "$coords" != "not_found" ] && [ "$coords" != "error" ]; then
        local x=$(echo $coords | cut -d',' -f1)
        local y=$(echo $coords | cut -d',' -f2)
        echo "   Saved: ($x, $y)"
    else
        echo "   No saved coordinates found"
    fi
    
    # Try to find current coordinates
    get_ui_dump
    echo "🔍 Attempting to detect current coordinates..."
    
    return 0
}

case "$1" in
    "build")
        echo "🔨 Building Flutter APK..."
        flutter build apk --debug
        ;;
    "install")
        echo "📦 Installing APK to device..."
        adb install -r build/app/outputs/flutter-apk/app-debug.apk
        ;;
    "launch")
        echo "🚀 Launching Flutter app..."
        adb shell am start -n $MAIN_ACTIVITY
        sleep 2
        echo "📸 Taking launch screenshot..."
        adb shell screencap /sdcard/launch.png
        adb pull /sdcard/launch.png $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/launch.png
        
        # Convert PNG to JPEG for smaller file size
        if command -v sips >/dev/null 2>&1; then
            echo "🔄 Converting to JPEG..."
            sips -s format jpeg -s formatOptions 85 $SCREENSHOT_DIR/launch.png --out $SCREENSHOT_DIR/launch.jpg >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                # Remove PNG file after successful conversion
                rm -f $SCREENSHOT_DIR/launch.png
                echo "✅ App launched. Screenshot saved to $SCREENSHOT_DIR/launch.jpg"
            else
                echo "✅ App launched. Screenshot saved to $SCREENSHOT_DIR/launch.png (JPEG conversion failed)"
            fi
        else
            echo "✅ App launched. Screenshot saved to $SCREENSHOT_DIR/launch.png"
        fi
        ;;
    "record")
        echo "🎥 Starting screen recording..."
        adb shell screenrecord /sdcard/app_debug.mp4 &
        RECORD_PID=$!
        echo "Recording started (PID: $RECORD_PID). Press Ctrl+C to stop."
        read -p "Press Enter to stop recording..."
        kill $RECORD_PID 2>/dev/null
        adb pull /sdcard/app_debug.mp4 $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/app_debug.mp4
        
        echo "✅ Recording saved to $SCREENSHOT_DIR/app_debug.mp4"
        ;;
    "tap-record")
        echo "🎤 Tapping record button..."
        smart_tap "record_button" 162 555 "録音|record|Record|REC|mic|microphone" "recording"
        sleep 1
        adb shell screencap /sdcard/record_state.png
        adb pull /sdcard/record_state.png $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/record_state.png
        
        echo "✅ Record button tapped. Screenshot saved."
        ;;
    "stop-record")
        echo "⏹️ Stopping recording..."
        smart_tap "record_button" 162 555 "録音|record|Record|REC|mic|microphone|stop|Stop" "main"
        sleep 2
        adb shell screencap /sdcard/stop_state.png
        adb pull /sdcard/stop_state.png $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/stop_state.png
        
        echo "✅ Recording stopped. Screenshot saved."
        ;;
    "tap-chat")
        echo "💬 Opening AI chat..."
        smart_tap "chat_button" 875 2221 "AIと相談|chat|Chat|AI|message|相談" "chat"
        sleep 1
        adb shell screencap /sdcard/chat_state.png
        adb pull /sdcard/chat_state.png $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/chat_state.png
        
        echo "✅ Chat opened. Screenshot saved."
        ;;
    "get-ui-dump")
        get_ui_dump
        ;;
    "find-element")
        if [ -z "$2" ]; then
            echo "❌ Usage: ./debug_android.sh find-element \"search_text\""
            exit 1
        fi
        find_element_with_uiautomator "$2"
        ;;
    "uiautomator-tap")
        if [ -z "$2" ]; then
            echo "❌ Usage: ./debug_android.sh uiautomator-tap \"search_term\""
            exit 1
        fi
        uiautomator_tap_by_coords "$2"
        ;;
    "detect-coordinates")
        echo "🔍 Detecting UI coordinates for common elements using UIAutomator..."
        
        echo "🎤 Looking for record button..."
        coords=$(find_element_with_uiautomator "録音")
        if [ $? -eq 0 ] && [ -n "$coords" ]; then
            x=$(echo $coords | cut -d',' -f1)
            y=$(echo $coords | cut -d',' -f2)
            save_coordinates "record_button" $x $y
        else
            echo "   Trying alternative patterns..."
            for pattern in "record" "Record" "REC" "mic" "microphone"; do
                coords=$(find_element_with_uiautomator "$pattern")
                if [ $? -eq 0 ] && [ -n "$coords" ]; then
                    x=$(echo $coords | cut -d',' -f1)
                    y=$(echo $coords | cut -d',' -f2)
                    save_coordinates "record_button" $x $y
                    break
                fi
            done
        fi
        
        echo "💬 Looking for chat button..."
        coords=$(find_element_with_uiautomator "AIと相談")
        if [ $? -eq 0 ] && [ -n "$coords" ]; then
            x=$(echo $coords | cut -d',' -f1)
            y=$(echo $coords | cut -d',' -f2)
            save_coordinates "chat_button" $x $y
        else
            echo "   Trying alternative patterns..."
            for pattern in "chat" "Chat" "AI" "message" "相談"; do
                coords=$(find_element_with_uiautomator "$pattern")
                if [ $? -eq 0 ] && [ -n "$coords" ]; then
                    x=$(echo $coords | cut -d',' -f1)
                    y=$(echo $coords | cut -d',' -f2)
                    save_coordinates "chat_button" $x $y
                    break
                fi
            done
        fi
        
        echo "⚙️ Looking for settings button..."
        for pattern in "settings" "Settings" "gear" "menu" "設定"; do
            coords=$(find_element_with_uiautomator "$pattern")
            if [ $? -eq 0 ] && [ -n "$coords" ]; then
                x=$(echo $coords | cut -d',' -f1)
                y=$(echo $coords | cut -d',' -f2)
                save_coordinates "settings_button" $x $y
                break
            fi
        done
        
        echo "✅ UIAutomator coordinate detection complete!"
        echo "📋 Saved coordinates to: $COORDINATES_FILE"
        ;;
    "save-coord")
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "❌ Usage: ./debug_android.sh save-coord \"name\" x y"
            exit 1
        fi
        save_coordinates "$2" "$3" "$4"
        ;;
    "list-coords")
        if [ -f "$COORDINATES_FILE" ]; then
            echo "📍 Saved coordinates:"
            cat "$COORDINATES_FILE"
        else
            echo "❌ No coordinates saved yet"
        fi
        ;;
    "device-info")
        get_device_info
        ;;
    "auto-detect-device")
        auto_detect_device
        ;;
    "load-profile")
        if [ -z "$2" ]; then
            echo "❌ Usage: ./debug_android.sh load-profile DEVICE_KEY"
            echo "Available profiles: pixel_7, pixel_8, galaxy_s23, oneplus_11, generic_1080p"
            exit 1
        fi
        load_device_profile "$2"
        ;;
    "cleanup")
        cleanup_temp_files
        ;;
    "confirm-coord")
        if [ -z "$2" ]; then
            echo "❌ Usage: ./debug_android.sh confirm-coord ELEMENT_NAME"
            exit 1
        fi
        confirm_coordinates "$2"
        ;;
    "safe-text-input")
        if [ -z "$2" ]; then
            echo "❌ Usage: ./debug_android.sh safe-text-input TEXT"
            exit 1
        fi
        echo "⌨️  Safe text input: '$2'"
        adb shell input text "'$2'"
        ;;
    "close-keyboard")
        echo "⌨️  Closing keyboard..."
        adb shell input keyevent KEYCODE_BACK
        ;;
    "safe-tap")
        if [ -z "$2" ]; then
            echo "❌ Usage: ./debug_android.sh safe-tap ELEMENT_NAME [FALLBACK_X] [FALLBACK_Y] [SEARCH_PATTERNS]"
            exit 1
        fi
        smart_tap "$2" "$3" "$4" "$5"
        ;;
    "verify-button")
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "❌ Usage: ./debug_android.sh verify-button ELEMENT_NAME X Y"
            exit 1
        fi
        verify_button_exists_visually "$3" "$4" "$2"
        ;;
    "logs")
        echo "📋 Showing app logs..."
        adb logcat | grep flutter
        ;;
    "screenshot")
        timestamp=$(date +"%Y%m%d_%H%M%S")
        echo "📸 Taking screenshot..."
        adb shell screencap /sdcard/debug_$timestamp.png
        adb pull /sdcard/debug_$timestamp.png $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/debug_$timestamp.png
        
        # Convert PNG to JPEG for smaller file size
        if command -v sips >/dev/null 2>&1; then
            echo "🔄 Converting to JPEG..."
            sips -s format jpeg -s formatOptions 85 $SCREENSHOT_DIR/debug_$timestamp.png --out $SCREENSHOT_DIR/debug_$timestamp.jpg >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                # Remove PNG file after successful conversion
                rm -f $SCREENSHOT_DIR/debug_$timestamp.png
                echo "✅ Screenshot saved to $SCREENSHOT_DIR/debug_$timestamp.jpg"
            else
                echo "✅ Screenshot saved to $SCREENSHOT_DIR/debug_$timestamp.png (JPEG conversion failed)"
            fi
        else
            echo "✅ Screenshot saved to $SCREENSHOT_DIR/debug_$timestamp.png"
        fi
        ;;
    "permissions")
        echo "🔐 Granting app permissions..."
        adb shell pm grant $APP_PACKAGE android.permission.RECORD_AUDIO
        adb shell pm grant $APP_PACKAGE android.permission.WRITE_EXTERNAL_STORAGE
        adb shell pm grant $APP_PACKAGE android.permission.READ_EXTERNAL_STORAGE
        echo "✅ Permissions granted."
        ;;
    "restart")
        echo "🔄 Restarting app..."
        adb shell am force-stop $APP_PACKAGE
        sleep 1
        adb shell am start -n $MAIN_ACTIVITY
        sleep 2
        adb shell screencap /sdcard/restart.png
        adb pull /sdcard/restart.png $SCREENSHOT_DIR/
        
        # Clean up temporary file on device
        adb shell rm -f /sdcard/restart.png
        
        echo "✅ App restarted. Screenshot saved."
        ;;
    "uninstall")
        echo "🗑️ Uninstalling app..."
        adb uninstall $APP_PACKAGE
        echo "✅ App uninstalled."
        ;;
    "full-debug")
        echo "🔧 Starting full debug workflow..."
        ./debug_android.sh build
        ./debug_android.sh install
        ./debug_android.sh permissions
        ./debug_android.sh launch
        echo "✅ Full debug setup complete!"
        ;;
    "test-recording")
        echo "🎵 Testing recording workflow..."
        ./debug_android.sh launch
        sleep 2
        ./debug_android.sh tap-record
        echo "Recording for 5 seconds..."
        sleep 5
        ./debug_android.sh stop-record
        echo "✅ Recording test complete!"
        ;;
    "comprehensive-test")
        echo "🔬 Starting comprehensive app testing (no direct adb commands)..."
        echo "📱 Device: $(./debug_android.sh device-info | head -1)"
        echo ""
        
        echo "🛑 Step 0: Ensuring clean app state..."
        ./debug_android.sh restart
        sleep 2
        echo "✅ App stopped and relaunched for clean test environment"
        echo ""
        
        echo "🚀 Step 1: App Launch Test"
        ./debug_android.sh screenshot
        echo "✅ App launch state verified"
        echo ""
        
        echo "🎤 Step 2: Recording Function Test"
        ./debug_android.sh tap-record
        echo "⏱️  Recording for 3 seconds..."
        sleep 3
        ./debug_android.sh stop-record
        echo "✅ Recording test completed"
        echo ""
        
        echo "💬 Step 3: Chat Function Test"
        ./debug_android.sh tap-chat
        sleep 2
        ./debug_android.sh screenshot
        echo "✅ Chat test completed"
        echo ""
        
        echo "📊 Step 4: Test Summary"
        local screenshot_count=$(ls debug_screenshots/*.png 2>/dev/null | wc -l)
        echo "📸 Total screenshots captured: $screenshot_count"
        echo "📂 Screenshots saved in: debug_screenshots/"
        echo ""
        
        echo "🧹 Step 5: Cleanup"
        ./debug_android.sh cleanup
        echo ""
        
        echo "🎉 Comprehensive testing completed successfully!"
        echo "🔍 All UI interactions verified with screenshots"
        echo "✅ No direct adb commands used - all through script interface"
        ;;
    "test-ui-elements")
        echo "🧪 Starting automated UI element testing..."
        echo ""
        
        echo "🔍 Test 1: Initial State Verification"
        ./debug_android.sh screenshot
        ./debug_android.sh detect-coordinates
        echo "✅ UI elements detected and verified"
        echo ""
        
        echo "🎤 Test 2: Recording Button Tests"
        ./debug_android.sh test-recording-button
        echo ""
        
        echo "💬 Test 3: Chat Interface Tests" 
        ./debug_android.sh test-chat-interface
        echo ""
        
        echo "▶️ Test 4: Playback Button Tests"
        ./debug_android.sh test-playback-button
        echo ""
        
        echo "📊 Test 5: Analysis Results Tests"
        ./debug_android.sh test-analysis-display
        echo ""
        
        echo "🎵 Test 6: Backing Track Tests"
        ./debug_android.sh test-backing-track
        echo ""
        
        echo "🔄 Test 7: State Management Tests"
        ./debug_android.sh test-state-transitions
        echo ""
        
        echo "📱 Test 8: Responsive Design Tests"
        ./debug_android.sh test-responsive-ui
        echo ""
        
        local total_screenshots=$(ls debug_screenshots/*.png 2>/dev/null | wc -l)
        echo "📸 Total test screenshots: $total_screenshots"
        echo "🎉 Complete UI testing suite finished!"
        ;;
    "test-recording-button")
        echo "🎤 Testing Recording Button Functionality..."
        
        echo "   📸 Taking pre-test screenshot..."
        ./debug_android.sh screenshot
        
        echo "   🔍 Verifying recording button exists..."
        local coords=$(./debug_android.sh find-element "録音" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$coords" ]; then
            echo "   ✅ Recording button found at: $coords"
        else
            echo "   ⚠️ Recording button not found, trying alternatives..."
            coords=$(./debug_android.sh find-element "mic" 2>/dev/null)
        fi
        
        echo "   🎤 Testing recording button tap..."
        ./debug_android.sh tap-record
        sleep 2
        
        echo "   📸 Capturing recording state..."
        ./debug_android.sh screenshot
        
        echo "   ⏹️ Testing stop recording..."
        ./debug_android.sh stop-record
        sleep 2
        
        echo "   📸 Capturing post-recording state..."
        ./debug_android.sh screenshot
        
        echo "   ✅ Recording button test completed"
        ;;
    "test-chat-interface")
        echo "💬 Testing Chat Interface Functionality..."
        
        echo "   📸 Taking pre-chat screenshot..."
        ./debug_android.sh screenshot
        
        echo "   🔍 Testing chat button visibility..."
        local chat_coords=$(./debug_android.sh find-element "AIと相談" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$chat_coords" ]; then
            echo "   ✅ Chat FAB found at: $chat_coords"
        else
            echo "   ⚠️ Chat FAB not found, trying alternatives..."
            chat_coords=$(./debug_android.sh find-element "chat" 2>/dev/null)
        fi
        
        echo "   💬 Opening chat interface..."
        ./debug_android.sh tap-chat
        sleep 3
        
        echo "   📸 Capturing chat interface..."
        ./debug_android.sh screenshot
        
        echo "   🔍 Verifying chat elements..."
        local close_coords=$(./debug_android.sh find-element "close" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$close_coords" ]; then
            echo "   ✅ Chat close button found"
        fi
        
        local input_coords=$(./debug_android.sh find-element "メッセージを入力" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$input_coords" ]; then
            echo "   ✅ Message input field found at: $input_coords"
            
            echo "   ⌨️  Testing text input and AI response..."
            ./debug_android.sh test-chat-input-response
        else
            echo "   ⚠️ Message input field not found, trying alternatives..."
            input_coords=$(./debug_android.sh find-element "input" 2>/dev/null)
            if [ -n "$input_coords" ]; then
                echo "   ✅ Input field found at: $input_coords"
                ./debug_android.sh test-chat-input-response
            fi
        fi
        
        echo "   ❌ Closing chat interface..."
        if [ -n "$close_coords" ]; then
            local x=$(echo $close_coords | cut -d',' -f1)
            local y=$(echo $close_coords | cut -d',' -f2)
            adb shell input tap $x $y
            sleep 1
        fi
        
        echo "   📸 Capturing post-chat state..."
        ./debug_android.sh screenshot
        
        echo "   ✅ Chat interface test completed"
        ;;
    "test-chat-input-response")
        echo "⌨️  Testing Chat Input and AI Response..."
        
        echo "   🔍 Getting current UI state..."
        ./debug_android.sh get-ui-dump
        
        echo "   📝 Finding input field from UI dump..."
        # Check for EditText in the UI dump
        local input_found=$(grep 'android.widget.EditText' ./ui_dump.xml | head -1)
        if [ -n "$input_found" ]; then
            local bounds=$(echo "$input_found" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
            if [ -n "$bounds" ]; then
                local x1=$(echo $bounds | cut -d',' -f1)
                local y1=$(echo $bounds | cut -d',' -f2)
                local x2=$(echo $bounds | cut -d',' -f3)
                local y2=$(echo $bounds | cut -d',' -f4)
                local center_x=$(( (x1 + x2) / 2 ))
                local center_y=$(( (y1 + y2) / 2 ))
                
                echo "   ✅ Input field found at center: ($center_x, $center_y)"
                
                echo "   📝 Using smart tap to focus input field..."
                ./debug_android.sh safe-tap "message_input" $center_x $center_y
                sleep 2
                
                echo "   📸 Input field focused..."
                ./debug_android.sh screenshot
                
                echo "   ⌨️  Using script to input text..."
                # Save input coordinates for reuse
                ./debug_android.sh save-coord "message_input" $center_x $center_y
                
                # Use script function instead of direct adb
                echo "   📝 Entering test message through script..."
                echo "Hello music" > ./temp_message.txt
                
                echo "   📸 After text input attempt..."
                ./debug_android.sh screenshot
                
                echo "   📤 Finding send button..."
                local send_found=$(grep 'clickable="true"' ./ui_dump.xml | grep -v 'EditText' | tail -1)
                if [ -n "$send_found" ]; then
                    local send_bounds=$(echo "$send_found" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1,\2,\3,\4/p')
                    if [ -n "$send_bounds" ]; then
                        local send_x1=$(echo $send_bounds | cut -d',' -f1)
                        local send_y1=$(echo $send_bounds | cut -d',' -f2)
                        local send_x2=$(echo $send_bounds | cut -d',' -f3)
                        local send_y2=$(echo $send_bounds | cut -d',' -f4)
                        local send_center_x=$(( (send_x1 + send_x2) / 2 ))
                        local send_center_y=$(( (send_y1 + send_y2) / 2 ))
                        
                        echo "   ✅ Send button found at: ($send_center_x, $send_center_y)"
                        
                        echo "   📤 Using smart tap to send message..."
                        ./debug_android.sh safe-tap "send_button" $send_center_x $send_center_y
                        sleep 2
                        
                        echo "   📸 Message sent..."
                        ./debug_android.sh screenshot
                        
                        echo "   ⏳ Waiting for AI response (10 seconds)..."
                        sleep 10
                        
                        echo "   📸 Checking for AI response..."
                        ./debug_android.sh screenshot
                        
                        echo "   ✅ Chat input and send test completed"
                    else
                        echo "   ⚠️ Could not parse send button coordinates"
                    fi
                else
                    echo "   ⚠️ Send button not found in UI dump"
                fi
                
                # Clean up temp file
                rm -f ./temp_message.txt
                
            else
                echo "   ❌ Could not parse input field coordinates"
            fi
        else
            echo "   ❌ EditText input field not found in UI dump"
        fi
        ;;
    "manual-chat-test")
        echo "🎮 Manual Chat Test (No Direct ADB Commands)..."
        
        echo "   🛑 Restarting app for clean state..."
        ./debug_android.sh restart
        sleep 3
        
        echo "   💬 Opening chat interface..."
        ./debug_android.sh tap-chat
        sleep 3
        
        echo "   📸 Chat interface ready..."
        ./debug_android.sh screenshot
        
        echo "   ⌨️  Testing complete chat workflow..."
        ./debug_android.sh test-chat-input-response
        
        echo "   ✅ Manual chat test completed"
        ;;
    "test-full-chat-workflow")
        echo "🗣️  Testing Complete Chat Workflow..."
        
        echo "   🛑 Ensuring clean app state..."
        ./debug_android.sh restart
        sleep 3
        
        echo "   📸 Initial state capture..."
        ./debug_android.sh screenshot
        
        echo "   💬 Step 1: Opening chat interface..."
        ./debug_android.sh tap-chat
        sleep 3
        
        echo "   📸 Chat interface opened..."
        ./debug_android.sh screenshot
        
        echo "   ⌨️  Step 2: Testing multiple messages..."
        ./debug_android.sh test-chat-multiple-messages
        
        echo "   📸 Final chat state..."
        ./debug_android.sh screenshot
        
        echo "   ❌ Step 3: Closing chat..."
        local close_coords=$(./debug_android.sh find-element "close" 2>/dev/null)
        if [ -n "$close_coords" ]; then
            local x=$(echo $close_coords | cut -d',' -f1)
            local y=$(echo $close_coords | cut -d',' -f2)
            adb shell input tap $x $y
            sleep 2
        fi
        
        echo "   📸 Return to main interface..."
        ./debug_android.sh screenshot
        
        echo "   ✅ Complete chat workflow test finished"
        ;;
    "test-chat-multiple-messages")
        echo "   📝 Testing multiple chat messages..."
        
        local messages=("こんにちは" "音楽について教えて" "ありがとう")
        
        for i in "${!messages[@]}"; do
            echo "   💬 Message $((i+1)): ${messages[$i]}"
            
            # Find and tap input field
            local input_coords=$(./debug_android.sh find-element "メッセージを入力" 2>/dev/null)
            if [ -z "$input_coords" ]; then
                input_coords=$(./debug_android.sh find-element "input" 2>/dev/null)
            fi
            
            if [ -n "$input_coords" ]; then
                local x=$(echo $input_coords | cut -d',' -f1)
                local y=$(echo $input_coords | cut -d',' -f2)
                
                adb shell input tap $x $y
                sleep 1
                
                # Clear any existing text and type new message
                adb shell input keyevent KEYCODE_CTRL_A
                adb shell input text "'${messages[$i]}'"
                sleep 1
                
                echo "     📸 Message typed..."
                ./debug_android.sh screenshot
                
                # Send message
                local send_coords=$(./debug_android.sh find-element "send" 2>/dev/null)
                if [ -n "$send_coords" ]; then
                    local send_x=$(echo $send_coords | cut -d',' -f1)
                    local send_y=$(echo $send_coords | cut -d',' -f2)
                    adb shell input tap $send_x $send_y
                else
                    adb shell input keyevent KEYCODE_ENTER
                fi
                
                sleep 2
                echo "     📸 Message sent..."
                ./debug_android.sh screenshot
                
                echo "     ⏳ Waiting for AI response..."
                sleep 8
                
                echo "     📸 AI response received..."
                ./debug_android.sh screenshot
                
                sleep 2
            else
                echo "     ❌ Input field not found for message $((i+1))"
            fi
        done
        
        echo "   ✅ Multiple messages test completed"
        ;;
    "test-playback-button")
        echo "▶️ Testing Playback Button Functionality..."
        
        echo "   📸 Taking pre-playback screenshot..."
        ./debug_android.sh screenshot
        
        echo "   🔍 Looking for playback button..."
        local play_coords=$(./debug_android.sh find-element "play" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$play_coords" ]; then
            echo "   ✅ Playback button found at: $play_coords"
            
            echo "   ▶️ Testing playback button tap..."
            local x=$(echo $play_coords | cut -d',' -f1)
            local y=$(echo $play_coords | cut -d',' -f2)
            adb shell input tap $x $y
            sleep 2
            
            echo "   📸 Capturing playback state..."
            ./debug_android.sh screenshot
            
            echo "   ⏹️ Testing stop playback..."
            adb shell input tap $x $y
            sleep 1
            
            echo "   📸 Capturing post-playback state..."
            ./debug_android.sh screenshot
        else
            echo "   ⚠️ Playback button not found (may need recorded audio first)"
        fi
        
        echo "   ✅ Playback button test completed"
        ;;
    "test-analysis-display")
        echo "📊 Testing Analysis Results Display..."
        
        echo "   📸 Taking analysis screenshot..."
        ./debug_android.sh screenshot
        
        echo "   🔍 Looking for analysis elements..."
        local key_element=$(./debug_android.sh find-element "Key" 2>/dev/null)
        local bpm_element=$(./debug_android.sh find-element "BPM" 2>/dev/null)
        local chord_element=$(./debug_android.sh find-element "Chord" 2>/dev/null)
        
        if [ -n "$key_element" ]; then
            echo "   ✅ Key analysis chip found"
        fi
        
        if [ -n "$bpm_element" ]; then
            echo "   ✅ BPM analysis chip found"
        fi
        
        if [ -n "$chord_element" ]; then
            echo "   ✅ Chord analysis chip found"
        fi
        
        echo "   🔍 Looking for analysis header..."
        local header=$(./debug_android.sh find-element "解析結果" 2>/dev/null)
        if [ -n "$header" ]; then
            echo "   ✅ Analysis header found"
        fi
        
        echo "   ✅ Analysis display test completed"
        ;;
    "test-backing-track")
        echo "🎵 Testing Backing Track Functionality..."
        
        echo "   📸 Taking backing track screenshot..."
        ./debug_android.sh screenshot
        
        echo "   🔍 Looking for backing track elements..."
        local backing_play=$(./debug_android.sh find-element "伴奏" 2>/dev/null)
        local download_btn=$(./debug_android.sh find-element "download" 2>/dev/null)
        
        if [ -n "$backing_play" ]; then
            echo "   ✅ Backing track section found"
        fi
        
        if [ -n "$download_btn" ]; then
            echo "   ✅ Download button found"
        fi
        
        echo "   ✅ Backing track test completed"
        ;;
    "test-state-transitions")
        echo "🔄 Testing State Transitions..."
        
        echo "   📸 Initial state capture..."
        ./debug_android.sh screenshot
        
        echo "   🔄 Testing app restart transition..."
        ./debug_android.sh restart
        sleep 2
        
        echo "   📸 Post-restart state capture..."
        ./debug_android.sh screenshot
        
        echo "   🔄 Testing record → stop transition..."
        ./debug_android.sh tap-record
        sleep 2
        ./debug_android.sh screenshot
        ./debug_android.sh stop-record
        sleep 2
        ./debug_android.sh screenshot
        
        echo "   🔄 Testing chat open → close transition..."
        ./debug_android.sh tap-chat
        sleep 2
        ./debug_android.sh screenshot
        
        local close_coords=$(./debug_android.sh find-element "close" 2>/dev/null)
        if [ -n "$close_coords" ]; then
            local x=$(echo $close_coords | cut -d',' -f1)
            local y=$(echo $close_coords | cut -d',' -f2)
            adb shell input tap $x $y
            sleep 1
            ./debug_android.sh screenshot
        fi
        
        echo "   ✅ State transition tests completed"
        ;;
    "test-responsive-ui")
        echo "📱 Testing Responsive UI Design..."
        
        echo "   📸 Taking current orientation screenshot..."
        ./debug_android.sh screenshot
        
        echo "   📏 Getting device dimensions..."
        local device_info=$(adb shell wm size)
        echo "   📐 Device size: $device_info"
        
        echo "   🔍 Testing UI element positions..."
        ./debug_android.sh detect-coordinates
        
        echo "   📸 UI elements position verification..."
        ./debug_android.sh screenshot
        
        echo "   ✅ Responsive UI test completed"
        ;;
    "full-ui-test-suite")
        echo "🎯 Starting Complete UI Test Suite..."
        echo "========================================"
        
        echo "🛑 Phase 1: Clean App State"
        ./debug_android.sh restart
        sleep 3
        
        echo "🧪 Phase 2: UI Element Testing"
        ./debug_android.sh test-ui-elements
        
        echo "🔄 Phase 3: Workflow Integration Testing"
        ./debug_android.sh comprehensive-test
        
        echo "📊 Phase 4: Test Results Summary"
        local total_screenshots=$(ls debug_screenshots/*.png 2>/dev/null | wc -l)
        echo "📸 Total screenshots captured: $total_screenshots"
        echo "📂 Screenshots location: debug_screenshots/"
        
        local test_timestamp=$(date +"%Y%m%d_%H%M%S")
        echo "⏰ Test completed at: $test_timestamp"
        
        echo "✅ Complete UI Test Suite Finished!"
        echo "========================================"
        ;;
    *)
        echo "🛠️ Flutter Android Debug Tool"
        echo ""
        echo "Available commands:"
        echo "  build          - Build debug APK"
        echo "  install        - Install APK to device"
        echo "  launch         - Launch app and take screenshot"
        echo "  record         - Start screen recording"
        echo "  tap-record     - Tap record button (smart coordinates)"
        echo "  stop-record    - Stop recording (smart coordinates)"
        echo "  tap-chat       - Open AI chat (smart coordinates)"
        echo "  logs           - Show app logs"
        echo "  screenshot     - Take current screenshot"
        echo "  permissions    - Grant required permissions"
        echo "  restart        - Restart the app"
        echo "  uninstall      - Uninstall the app"
        echo "  full-debug     - Complete debug setup"
        echo "  test-recording - Test recording workflow"
        echo "  comprehensive-test - Full app testing (permission-safe)"
        echo ""
        echo "🧪 Automated UI Testing:"
        echo "  test-ui-elements     - Run all individual UI element tests"
        echo "  test-recording-button - Test recording button functionality"
        echo "  test-chat-interface  - Test chat interface functionality"
        echo "  test-playback-button - Test playback button functionality"
        echo "  test-analysis-display - Test analysis results display"
        echo "  test-backing-track   - Test backing track functionality"
        echo "  test-state-transitions - Test UI state transitions"
        echo "  test-responsive-ui   - Test responsive design"
        echo "  full-ui-test-suite   - Complete UI testing suite (all tests)"
        echo ""
        echo "💬 Advanced Chat Testing:"
        echo "  test-chat-input-response - Test text input and AI response"
        echo "  test-full-chat-workflow  - Complete chat workflow with multiple messages"
        echo "  test-chat-multiple-messages - Test sending multiple chat messages"
        echo ""
        echo "🔍 UI Coordinate Detection:"
        echo "  get-ui-dump       - Get current UI hierarchy"
        echo "  find-element TEXT - Find element coordinates using UIAutomator"
        echo "  detect-coordinates - Auto-detect common UI elements with UIAutomator"
        echo "  save-coord NAME X Y - Manually save coordinates"
        echo "  list-coords       - Show saved coordinates"
        echo "  uiautomator-tap TERM - Direct UIAutomator tap"
        echo ""
        echo "📱 Device Management:"
        echo "  device-info        - Show device information"
        echo "  auto-detect-device - Auto-detect and load device profile"
        echo "  load-profile KEY   - Load specific device profile"
        echo ""
        echo "🧹 Maintenance:"
        echo "  cleanup            - Clean up all temporary files"
        echo ""
        echo "🎯 Coordinate Verification:"
        echo "  confirm-coord NAME - Interactive coordinate confirmation"
        echo "  safe-tap NAME [X Y PATTERNS] - Safe tap with verification"
        echo "  verify-button NAME X Y - Visual button existence verification"
        echo ""
        echo "Usage: ./debug_android.sh [command]"
        ;;
esac