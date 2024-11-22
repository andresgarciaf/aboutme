#!/bin/bash
clear

# variables
REPO="databricks-industry-solutions/security-analysis-tool"
DOWNLOAD_DIR="./"
INSTALLATION_DIR="sat-installer"
PYTHON_BIN="python3.11"
ENV_NAME=".env"

# Functions
download_latest_release() {
    local release_info file_name file_path

    release_info=$(curl --silent "https://api.github.com/repos/$REPO/releases/latest")
    url=$(echo "$release_info" | grep '"zipball_url"' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$url" ]]; then
        echo "Failed to fetch the latest release URL for SAT."
        exit 1
    fi

    # shellcheck disable=SC2155
    file_name="$(basename "$url").zip"
    file_path="$DOWNLOAD_DIR/$file_name"
    curl -s -L "$url" -o "$file_path" || { echo "Error: Failed to download $url"; exit 1; }

    echo "$file_path"
}

setup_sat() {
    echo "Downloading the latest release of SAT..."
    local file_path
    file_path=$(download_latest_release)

    if ls "$DOWNLOAD_DIR"/$INSTALLATION_DIR* 1>/dev/null 2>&1; then
        # shellcheck disable=SC2115
        rm -rf "$DOWNLOAD_DIR/$INSTALLATION_DIR"
    fi

    mkdir -p "$INSTALLATION_DIR"

    if [[ "$file_path" == *.zip ]]; then
        temp_dir=$(mktemp -d)

        echo "Extracting SAT..."
        unzip -q "$file_path" -d "$temp_dir" || { echo "Error: Failed to extract $file_path"; exit 1; }

        solution_dir=$(find "$temp_dir" -type d -name "databricks-industry-solutions*")

        if [[ -d "$solution_dir" ]]; then
            for folder in terraform src notebooks dashboards dabs configs; do
                if [[ -d "$solution_dir/$folder" ]]; then
                    cp -r "$solution_dir/$folder" "$INSTALLATION_DIR"
                fi
            done
        else
            echo "Error: No 'databricks-industry-solutions' folder found in the extracted contents."
            rm -rf "$temp_dir"
            return 1
        fi

        rm -rf "$temp_dir"
    fi

    rm "$file_path"
}

setup_env(){
    # Check  if Python is installed
    if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
        echo "Python 3.11 not found. Trying to find another Python 3 interpreter..."
        PYTHON_BIN="python3"
        if ! command_exists "$PYTHON_BIN"; then
            echo "No suitable Python interpreter found. Please install Python 3.11 or Python 3."
            exit 1
        fi
        echo "Using $PYTHON_BIN as a fallback."
    fi

    # Change to the script's directory
    cd "$INSTALLATION_DIR" || { echo "Failed to change directory to $INSTALLATION_DIR"; exit 1; }

    # Create virtual environment
    echo "Creating virtual environment $INSTALLATION_DIR/$ENV_NAME..."
    if ! "$PYTHON_BIN" -m venv "$ENV_NAME"; then
        echo "Failed to create virtual environment. Ensure Python 3.11 or Python 3 is properly installed."
        exit 1
    fi

    # Activate the virtual environment
    source "$ENV_NAME/bin/activate" || { echo "Failed to activate virtual env."; exit 1; }

    # Update pip, setuptools, and wheel
    echo "Updating pip, setuptools, and wheel..."
    if ! pip install --upgrade pip setuptools wheel -qqq; then
        echo "Failed to update libraries. Check your network connection and try again."
        exit 1
    fi
}

install_sat(){
  clear
  echo "--------------------------------"
  echo "How do you want to install SAT?"
  echo "1) Via Terraform"
  echo "2) Via Terminal"
  echo "--------------------------------"
  read -p "Please enter 1 or 2: " choice


  case $choice in
    1)
      echo "You chose to install via Terraform."
      # Add your Terraform installation logic here
      echo "Running Terraform script..."
      ;;
    2)
      echo "You chose to install via Terminal."
      # Add your terminal installation logic here
      echo "Running terminal installation commands..."
      ;;
    *)
      echo "Invalid choice. Please run the script again and select 1 or 2."
      ;;
  esac

}

main(){
    if [[ -d "docs" || -d "images" || -n "$(find . -maxdepth 1 -name '*.md' -o -name 'LICENSE' -o -name 'NOTICE')" ]]; then
        install_sat
    else
        setup_sat
        setup_env
        install_sat
    fi
}

# ----------- Main Script -----------
main
# ----------- Main Script -----------

