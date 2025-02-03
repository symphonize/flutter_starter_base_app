#!/bin/bash

# Metadata
# Version: 2025.05.143910+28334a4

# Path to the project directory
PROJECT_PATH="$(pwd)"

# Default build mode for the Flutter project
ENVIRONMENT="dev"

# Configuration file in the repository
CONFIG_FILE=".fvmrc"

env_file=".env/$ENVIRONMENT.json"

# Get the terminal width
TERMINAL_WIDTH=$(tput cols)

# Separator line based on the terminal width
SEPARATOR=$(printf '%*s' "$TERMINAL_WIDTH" '' | tr ' ' '═')

# Process the input arguments to extract dev/prod/staging and handle the rest: Array to store the remaining arguments
processed_args=()

on_auto_mode=

# Function to update the separator line whenever the terminal width changes
update_separator() { SEPARATOR=$(printf '%*s' "$(tput cols)" '' | tr ' ' '═'); }
trap update_separator SIGWINCH

# Colors for output
log_prompt() {
    local log_type="$1"
    local message="$2"
    # Define color codes for prompt text
    case "$log_type" in
    bold) color="\033[1;37m" ;;    # Bold White
    success) color="\033[1;32m" ;; # Bold Green
    warning) color="\033[1;33m" ;; # Bold Yellow
    error) color="\033[1;31m" ;;   # Bold Red
    cyan) color="\033[1;36m" ;;    # Bold Cyan
    blue) color="\033[1;34m" ;;    # Bold Blue
    magenta) color="\033[1;35m" ;; # Bold Magenta
    *) color="\033[0m" ;;          # Default (no color)
    esac
    # Return the formatted prompt text
    echo -e "${color}${message}\033[0m"
}
# Use log_prompt for consistent formatting
log_message() { log_prompt "$1" "$2"; }
log_header() { log_message "bold" "$1"; }
log_success() { log_message "success" "$1"; }
log_warning() { log_message "warning" "$1"; }
log_error() { log_message "error" "$1"; }
# Function to display the usage information of the script
show_help() {
    cat <<EOF

Usage: $0 [COMMAND] [ENVIRONMENT]

Commands:

1) create-app              - Creates necessary build files and platform files
2) create-icon             - Builds launch icon based on platform files.   
3) create-splash           - Creates necessary build files and platform files
4) run                     - Run the Flutter app on target device ${FLUTTER_TARGET_DEVICE:-[$FLUTTER_TARGET_DEVICE]}
5) build                   - Build the generated files, icons, splash, locale keys
6) test                    - Run tests for the Flutter app
7) clean                   - Clean the build directory
8) deploy                  - Deploy the Flutter app to a device or server
9) fvm_info                - Check the Flutter version using FVM
10) help                   - Displays available commands

Environment Variables:
  LOG_DIR        Base directory for log files.
  RELEASE_DIR    Directory for release builds (default: flutter default).

Examples:
  $0 build
  $0 test prod
  $0 staging create-app 

Note: [ENVIRONMENT] is optional. If not provided, the default environment [dev] will be used. 
        Available options [dev | staging | prod].

NOTE: If non-flutter libraries/packages are not recognized, you might need to reload the IDE

NOTE: create-icon creates flutter_launcher_icons.yaml file if it doesn't exist and set icon to assets/launch_icon.ico
      Sets platform values based on the presence of ios and android folders

NOTE: Some operations require 'jq' library

EOF
}

# Helper function to format and display a single menu item
format_menu_item() {
    local number="$1"
    local item="$2"
    local delimiter="|"

    # Extract the option and description using the custom delimiter
    IFS="$delimiter" read -r option description <<<"$item"

    # Print the formatted menu item with dynamic numbering
    printf "$(log_message "" ' %-3s %-25s %s\n')" "$number)" "$option" "$description"
}

interactive_menu() {
    local menu_items=(
        "Create Menu|Gives the options of thing this script supports creation of app file, launcer icon, splash screen"
        "Clean|Clean the build directory"
        "Build Application|Calls all the Required builders fully compile the application "
        "Test|Run tests for the Flutter app"
        "Package App Release|This will build and Sign a releasable App for the App Store"
        "Run|Run the Flutter app on target device. Run 'Set Device' to see the current device"
        "FVM Info|This will display the associated environment configuration to determine if it is configured correctly"
        "Set Device|Searches for avaialble android and ios devices. Sets first available as target device."
    )
    while true; do
        log_message "blue" "\n$SEPARATOR\n"
        log_header "Flutter App Manager ($ENVIRONMENT)\n"
        log_message "blue" "$SEPARATOR\n"
        # Header
        log_message "cyan" "Commands:"
        # Loop through menu items and format each one dynamically
        echo
        local count=1
        for item in "${menu_items[@]}"; do
            format_menu_item "$count" "$item"
            count=$((count + 1))
        done
        format_menu_item "Q" "Quit|Exit the application"
        read -r -p "$(log_warning "\nPlease select an option: ")" input
        case "$input" in
        1) create_menu || log_error "Error running $input" ;;
        2) run || log_error "Error running $input" ;;
        3) build || log_error "Error running $input" ;;
        4) test || log_error "Error running $input" ;;
        5) clean || log_error "Error running $input" ;;
        6) deploy || log_error "Error running $input" ;;
        7) fvm_info || log_error "Error running $input" ;;
        8) search_and_set_target_device || log_error "Error running $input" ;;
        q | Q) exit || log_error "Error running $input" ;;
        *)
            log_error "$SEPARATOR\n"
            log_error "Invalid option. Please try again or type 'q' to quit."
            ;;
        esac
    done
}
create_env_if_missing() {
    ENV_DIR=$(dirname "$ENV_FILE")
    ENV_FILE=".env/$ENVIRONMENT.json"
    if [[ ! -d "$ENV_DIR" ]]; then
        log_warning "Directory $ENV_DIR does not exist. Creating it."
        mkdir -p "$ENV_DIR"
    fi
    if [[ ! -f "$ENV_FILE" ]]; then
        log_warning "File $ENV_FILE does not exist. Creating it with dummy data."
        cat >"$ENV_FILE" <<EOF
{
  "API_URL": "https://api.example.com",
  "API_VERSION": {
    "HOST": "localhost",
    "PORT": 5432,
    "USER": "username",
    "PASSWORD": "password"
  },
  "LOG_LEVEL": "debug"
}
EOF
    fi
}
ios='ios'
android=
create_platform_specific_files() {
    read -r -p "$(log_warning "\nWould you like to create for ios? (y/n/c): ")" response
    echo
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if ! fvm flutter create --platforms ios .; then
            log_error "Unable to create ios files"
            return 1
        fi
    elif [[ "$response" =~ ^[Cc]$ ]]; then
        log_warning "\nReturning to menu\n"
        return 42
    fi
    read -r -p "$(log_warning "\nWould you like to create for android? (y/n/c): ")" response
    echo
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if ! fvm flutter create --platforms android .; then
            log_error "Unable to create android files"
            return 1
        fi
    elif [[ "$response" =~ ^[Cc]$ ]]; then
        log_warning "\nReturning to menu\n"
        return 42
    fi
}
create_menu() {
    local menu_items=(
        "Create App|Creates a Brand new Flutter App using our standards"
        "Create Icon|Creates a new Icon for the Mobile App"
        "Create Splash|Creates the Splash Screen for the Mobile App"
    )
    while true; do
        log_message "blue" "\n$SEPARATOR\n"
        log_header "Flutter App Manager ($ENVIRONMENT) => Create Menu\n"
        log_message "blue" "$SEPARATOR\n"
        # Header
        log_message "cyan" "Commands:"
        # Loop through menu items and format each one dynamically
        printf "\n"
        local count=1
        for item in "${menu_items[@]}"; do
            format_menu_item "$count" "$item"
            count=$((count + 1))
        done
        format_menu_item "C" "Cancel|Go back to previous menu"
        read -r -p "$(log_warning "\nPlease select an option: ")" input
        case "$input" in
        1) create_app || log_error "Error running $input" ;;
        2) build_app_icon || log_error "Error running $input" ;;
        3) build_splash_screen || log_error "Error running $input" ;;
        c | C) return ;;
        *)
            log_error "\n$SEPARATOR\n"
            log_error "Invalid option. Please try again or type "c" to return to main menu."
            ;;
        esac
    done
}
create_app() {
    echo -e "\n$(log_message "magenta" "$SEPARATOR")\n"
    create_env_if_missing
    create_fvm_if_missing
    create_platform_specific_files
    if [[ $? -eq 42 ]]; then
        return 0
    fi
    fvm flutter pub get
    build
}
# Shows current project, ide, environment configuration
fvm_info() {
    echo
    fvm doctor | while IFS= read -r line; do
        log_success "$line"
    done
}
create_fvm_if_missing() {
    if ! command -v fvm &>/dev/null; then
        log_error "\nFVM is not installed. Please install it using Homebrew."
        log_warning "\nRun the following command to install FVM:"
        log_message "cyan" "brew install fvm"
        read -r -p "$(log_prompt "yellow" "Would you like to install FVM now? (y/n): ")" response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            if ! command -v brew &>/dev/null; then
                log_error "Homebrew is not installed. Please install Homebrew first by visiting https://brew.sh."
                return 1
            else
                brew install fvm
                if [ $? -ne 0 ]; then
                    log_error "Failed to install FVM. Please try installing it manually."
                    return 1
                fi
                log_success "\nFVM installed successfully.\n"
            fi
        else
            log_error "Exiting. Please install FVM and try again."
            return 1
        fi
    fi
    log_message "" "\nLast 10 available stable Flutter versions:\n"
    fvm releases | tail -n 28 | sed '1s/^├.*┼.*┤$/ /; $s/^└.*┴.*┘$/ /'
    read -r -p "$(log_warning "Would you like to create a new configuration file? (y/n): ")" response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        read -r -p "$(log_warning "\nPlease select a Flutter version from the list above:") " selected_version
        log_success "\nConfiguration file $CONFIG_FILE created with version $selected_version.\n"
        fvm use $selected_version
    else
        log_error "Exiting. Please create the configuration file manually."
        return 1
    fi
    if ! command -v fvm &>/dev/null; then
        log_error "\nFVM is not installed. Please install FVM first by running:"
        log_warning "\nflutter pub global activate fvm\n"
        return 1
    fi
}
deploy() {
    log_success "$SEPARATOR\n"
    read -r -p "$(log_warning "Would you like to build generated files? (y/n) ")" response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        build
    fi
    case "$ENVIRONMENT" in
    dev | staging | prod) ;;
    *)
        log_error "Invalid envrionment!"
        return 1
        ;;
    esac
    env_file=".env/$ENVIRONMENT.json"
    if [[ ! -f "$env_file" ]]; then
        echo
        log_error "Environment file not found: $env_file"
        return 1
    fi
    echo
    log_message "" "Running flutter pub get to resolve dependencies..."
    fvm flutter pub get || {
        log_error "Failed to resolve dependencies. Check your pubspec.yaml."
        return 1
    }
    build_ios_release
    build_android_release
}
build() {
    log_warning "\nBuilding for $ENVIRONMENT"
    build_generated_files
    build_localization_keys
    log_success "\nBuild finished\n"
}
search_and_set_target_device() {
    log_message "blue" "\n$SEPARATOR\n"
    if [ -n "$FLUTTER_TARGET_DEVICE" ]; then
        log_success "\nCurrent device: $FLUTTER_TARGET_DEVICE"
        read -r -p "$(log_warning "\nRescan and set new device? (y/n): ")" response
        echo
        if [[ "$response" =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi
    log_message "magenta" "Scanning for devices...\n"
    DEVICE_LIST=$(fvm flutter devices --machine)
    if [[ -z "$DEVICE_LIST" || "$DEVICE_LIST" == "[]" ]]; then
        log_error "No device found"
        return 1
    fi
    FIRST_DEVICE=$(echo "$DEVICE_LIST" | jq -r '.[0].id')
    export FLUTTER_TARGET_DEVICE="$FIRST_DEVICE"
    DEVICE_INFO=$(flutter devices | grep "$FIRST_DEVICE")
    log_success "\nNew device set: $FLUTTER_TARGET_DEVICE"
}
test() {
    create_fvm_if_missing
    log_message "blue" "\n$SEPARATOR\n"
    log_message "magenta" "Running Flutter tests...\n"
    fvm flutter test
}
build_app_icon() {
    log_message "blue" "\n$SEPARATOR\n"
    log_message "magenta" "Running app icon builder...\n"
    if [[ ! -f "flutter_launcher_icons.yaml" ]]; then
        log_warning "flutter_launcher_icons.yaml does not exist. Creating file with assets/launch_icon.ico as the default."
        echo "flutter_launcher_icons:" >flutter_launcher_icons.yaml
        echo "  image_path: \"assets/launch_icon.ico\"" >>flutter_launcher_icons.yaml
    fi
    if [[ -d "ios" ]]; then
        if ! grep -q "ios: true" flutter_launcher_icons.yaml; then
            echo "  ios: true" >>flutter_launcher_icons.yaml
            log_warning "Added iOS configuration to flutter_launcher_icons.yaml."
        fi
    fi
    if [[ -d "android" ]]; then
        if ! grep -q "android: true" flutter_launcher_icons.yaml; then
            echo "  android: true" >>flutter_launcher_icons.yaml
            log_warning "Added Android configuration to flutter_launcher_icons.yaml."
        fi
    fi
    if ! fvm flutter pub run flutter_launcher_icons; then
        log_error "Failed to generate launch icons. Please check your configuration."
        return 1
    fi
    log_success "\nSuccessfully built icons"
}
build_splash_screen() {
    log_message "blue" "\n$SEPARATOR\n"
    log_message "magenta" "Running native splash screen builder..."
    if ! fvm dart run flutter_native_splash:create --path=flutter_native_splash.yaml; then
        log_error "Failed to generate splash screen. Please check your configuration."
        return 1
    fi
    log_success "\nSuccessfully built splash"
}
build_localization_keys() {
    log_message "blue" "\n$SEPARATOR\n"
    log_message "magenta" "Running easy localization builder...\n"
    if ! fvm dart run easy_localization:generate -S assets/locale -f keys -O $PROJECT_PATH/lib/src/localization/generated -o locale_keys.g.dart; then
        log_error "Failed to generate localization keys. Please check your configuration."
        return 1
    fi
    log_success "\nSuccessfully built localization keys"
}
build_generated_files() {
    log_message "blue" "\n$SEPARATOR\n"
    log_message "magenta" "Running build_runner...\n"
    if ! fvm flutter pub run build_runner build --delete-conflicting-outputs; then
        log_error "Failed to build generated files. Please check your configuration."
        return 1
    fi
    log_success "\nSuccessfully built generated files"
}
clean() {
    log_warning "\n$SEPARATOR\n"
    rm -rf build .dart_tool
    log_warning "Cleaning CocoaPods cache...\n"
    pod cache clean --all
    rm -rf ios/Pods ios/Podfile.lock || log_error "Failed to clean CocoaPods cache!"
    log_warning "Cleaning the build directory...\n"
    fvm flutter clean || {
        log_error "\nFailed to clean\n"
        return 1
    }
    echo -e "\033[H\033[J"
    log_success "\nSuccessfully cleaned"
}
run() {
    build
    log_message "magenta" "\nRunning with FVM Flutter...\n"
    fvm flutter run --dart-define-from-file=".env/$ENVIRONMENT.json"
    log_message "blue" "\n$SEPARATOR\n"
}
build_android_release() {
    # Check for the Android platform directory
    if [[ ! -d "android" ]]; then
        log_error "Android directory not found. Creating it with flutter create..."
        return 1
    fi
    log_warning "Starting the AAB build..."
    if ! fvm flutter build aab --release --dart-define-from-file="$env_file"; then
        log_error "Build failed. Please check the output above for details."
        return 1
    fi
}
build_ios_release() {
    log_success "Building Flutter project for iOS..."
    if [[ ! -d "ios" ]]; then
        log_error "\niOS folder not found. Please use Create App Menu to create iOS files\n"
        return 1
    fi
    # Ensure Flutter iOS-specific artifacts are up to date
    log_message "" "Precaching iOS-specific Flutter artifacts..."
    fvm flutter precache --ios || {
        log_error "Failed to precache iOS artifacts!"
        return 1
    }

    # Install CocoaPods dependencies
    log_message "" "Reinstalling CocoaPods dependencies..."
    (cd ios && pod install && cd ..) || {
        log_error "Failed to install CocoaPods dependencies!"
        return 1
    }

    # Build the iOS project
    log_message "" "Building the Flutter app for iOS..."
    fvm flutter build ipa --release --dart-define-from-file="$(pwd)/$env_file"
}
main() {
    for arg in "$@"; do
        case "$arg" in
        dev | prod | staging) ENVIRONMENT="$arg" ;;
        full-auto) on_auto_mode=true ;;
        *) processed_args+=("$arg") ;;
        esac
    done
    set -- "${processed_args[@]}"
    if [[ $# -lt 1 ]]; then
        interactive_menu
    else
        case "$1" in
        --help | help) show_help ;;
        create-app) create_app || log_error "Error running $1" ;;
        create-icon) build_app_icon || log_error "Error running $1" ;;
        create-splash) build_splash_screen || log_error "Error running $1" ;;
        run | build | test | deploy | clean | fvm_info) $1 || log_error "Error running $1" ;;
        *)
            log_error "\nUnknown command: $1"
            log_header "\nPlease use 'help' to see available commands.\n"
            ;;
        esac
    fi
}
main "$@"
