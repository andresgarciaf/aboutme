#!/bin/bash

# curl -fsSL https://raw.githubusercontent.com/jgarciaf106/jgarciaf106/main/install.sh -o install.sh
# sh install.sh

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

    # Create virtual environment
    if [[ ! -d "docs" && ! -d "images" && -z "$(find . -maxdepth 1 -name '*.md' -o -name 'LICENSE' -o -name 'NOTICE')" ]]; then
        cd $INSTALLATION_DIR || { echo "Failed to change directory to $INSTALLATION_DIR"; exit 1; }
        echo "Creating virtual environment $INSTALLATION_DIR/$ENV_NAME..."
    else
        echo "Creating virtual environment ./$ENV_NAME..."
    fi

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

update_tfvars() {
  local tfvars_file="terraform.tfvars"

  # Loop through the passed arguments and append to the tfvars file
  for var in "$@"; do
    var_name="${var%%=*}"
    var_value="${var#*=}"

    if [[ "$var_name" == "proxies" ]]; then
      echo "${var_name}=${var_value}" >> "$tfvars_file"
    else
      echo "${var_name}=\"${var_value}\"" >> "$tfvars_file"
    fi
  done

}

# functions to validate the inputs
validate_proxies() {
  [[ "$1" == "{}" || "$1" =~ ^\{\s*\"http\":\s*\"http://[^\"]+\",\s*\"https\":\s*\"http://[^\"]+\"\s*\}$ ]]
}

validate_workspace_id() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_analysis_schema_name() {
  [[ "$1" =~ ^([a-zA-Z0-9_]+\.[a-zA-Z0-9_]+|hive_metastore\.[a-zA-Z0-9_]+)$ ]]
}

validate_guid() {
    [[ "$1" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ && "${#1}" -eq 36 ]]
}

validate_client_secret() {
  [[ "${#1}" -eq 40 ]]
}

validate_databricks_url() {
    [[ "$1" =~ ^https://.*\.azuredatabricks\.net(/.*)?$ || \
       "$1" =~ ^https://.*\.cloud\.databricks\.com(/.*)?$ || \
       "$1" =~ ^https://.*\.gcp\.databricks\.com(/.*)?$ ]]
}

# Prompt user for Azure inputs and validate
#azure_validation() {}
#gcp_validation() {}
azure_validation() {
  local AZURE_SUBSCRIPTION_ID
  local AZURE_TENANT_ID
  local AZURE_CLIENT_ID
  local AZURE_CLIENT_SECRET
  local DATABRICKS_ACCOUNT_ID
  local AZURE_DATABRICKS_URL
  local AZURE_WORKSPACE_ID
  local ANALYSIS_SCHEMA_NAME
  local AZURE_PROXIES

  clear

  cd azure || { echo "Failed to change directory to azure"; exit 1; }

  echo "-------------------------------------------------------------------"
  echo "Setting up Azure environment, Please provide the following details:"
  echo "-------------------------------------------------------------------"
  echo

  # Prompt user and validate inputs
  read -p "Enter Azure Subscription ID: " AZURE_SUBSCRIPTION_ID
  while ! validate_guid "$AZURE_SUBSCRIPTION_ID"; do
    echo "Invalid Subscription ID."
    read -p "Enter Azure Subscription ID: " AZURE_SUBSCRIPTION_ID
  done

  read -p "Enter Azure Tenant ID: " AZURE_TENANT_ID
  while ! validate_guid "$AZURE_TENANT_ID"; do
    echo "Invalid Tenant ID."
    read -p "Enter Azure Tenant ID: " AZURE_TENANT_ID
  done

  read -p "Enter Azure Client ID: " AZURE_CLIENT_ID
  while ! validate_guid "$AZURE_CLIENT_ID"; do
    echo "Invalid Client ID."
    read -p "Enter Azure Client ID: " AZURE_CLIENT_ID
  done

  read -sp "Enter Azure Client Secret: " AZURE_CLIENT_SECRET
  while ! validate_client_secret "$AZURE_CLIENT_SECRET"; do
    echo "Invalid Client Secret."
    read -sp "Enter Azure Client Secret: " AZURE_CLIENT_SECRET
  done

  read -p "Enter Databricks Account ID: " DATABRICKS_ACCOUNT_ID
  while ! validate_guid "$DATABRICKS_ACCOUNT_ID"; do
    echo "Invalid Databricks Account ID."
    read -p "Enter Databricks Account ID: " DATABRICKS_ACCOUNT_ID
  done

  read -p "Enter Databricks URL: " AZURE_DATABRICKS_URL
  while ! validate_databricks_url "$AZURE_DATABRICKS_URL"; do
    echo "Invalid Databricks URL."
    read -p "Enter Databricks URL: " AZURE_DATABRICKS_URL
  done

  read -p "Enter Azure Workspace ID: " AZURE_WORKSPACE_ID
  while ! validate_workspace_id "$AZURE_WORKSPACE_ID"; do
    echo "Invalid Workspace ID."
    read -p "Enter Azure Workspace ID: " AZURE_WORKSPACE_ID
  done

  read -p "Enter Analysis Schema Name (e.g., 'catalog.schema' or 'hive_metastore.schema'): " ANALYSIS_SCHEMA_NAME
  while ! validate_analysis_schema_name "$ANALYSIS_SCHEMA_NAME"; do
      echo "Invalid Analysis Schema Name. It must be either 'catalog.schema' or 'hive_metastore.schema'."
      read -p "Enter Analysis Schema Name (e.g.,'catalog.schema' or 'hive_metastore.schema'): " ANALYSIS_SCHEMA_NAME
  done

  read -p "Enter Proxy Details ({} or JSON with 'http' and 'https' keys): " AZURE_PROXIES
  while ! validate_proxies "$AZURE_PROXIES"; do
    echo "Invalid Proxy format. Use '{}' or a valid JSON format like:"
    echo '{ "http": "http://proxy.example.com:8080", "https": "http://proxy.example.com:8080" }'
    read -p "Enter Proxy Details ({} or JSON with 'http' and 'https' keys): " AZURE_PROXIES
  done

  # Set variables for Azure arguments
  AZURE_VAR_ARGS=(
    "subscription_id=$AZURE_SUBSCRIPTION_ID"
    "tenant_id=$AZURE_TENANT_ID"
    "client_id=$AZURE_CLIENT_ID"
    "client_secret=$AZURE_CLIENT_SECRET"
    "account_console_id=$DATABRICKS_ACCOUNT_ID"
    "databricks_url=$AZURE_DATABRICKS_URL"
    "workspace_id=$AZURE_WORKSPACE_ID"
    "analysis_schema_name=$ANALYSIS_SCHEMA_NAME"
    "proxies=$AZURE_PROXIES"
  )

  update_tfvars "${AZURE_VAR_ARGS[@]}"
}

# shellcheck disable=SC2120
terraform_actions() {
  PLAN_FILE="tfplan"
  COMMON_ARGS=(
      -no-color
      -input=false
  )

  # Execute Terraform commands
  case $1 in
    "aws")
      aws_validation
      ;;
    "azure")
      azure_validation
      ;;
    "gcp")
      gcp_validation
      ;;
    *)
      echo "Invalid option."
      ;;
  esac

  terraform init "${COMMON_ARGS[@]}" || { echo "Failed to initialize Terraform."; exit 1; }
  terraform plan -out="$PLAN_FILE" "${COMMON_ARGS[@]}" || { echo "Failed to create a Terraform plan."; exit 1; }
  terraform apply -auto-approve "$PLAN_FILE" || { echo "Failed to apply the Terraform plan."; exit 1; }
}

terraform_install(){
  clear
  echo "Running Terraform installation..."
  cd terraform || { echo "Failed to change directory to terraform"; exit 1; }
  options=("AWS" "Azure" "GCP" "Quit")
  echo "Please select an option:"
  select opt in "${options[@]}"
  do
    case $opt in
      "AWS")
        terraform_actions "aws"
        ;;
      "Azure")
        terraform_actions "azure"
        ;;
      "GCP")
        terraform_actions "gcp"
        ;;
      "Quit")
        echo "Exiting SAT Installation..."
        break
        ;;
      *)
        echo "Invalid option."
        ;;
    esac
  done
}

shell_install(){
  echo "Running terminal installation..."

  cd dabs || { echo "Failed to change directory to dabs"; exit 1; }
  setup_env || { echo "Failed to setup virtual environment."; exit 1; }

  echo "Installing SAT dependencies..."
  pip install -r requirements.txt -qqq || { echo "Failed to install Python dependencies."; exit 1; }
  python main.py || { echo "Failed to run the main script."; exit 1; }
}

uninstall() {
  local tfplan_path databricks_path

  # Find a file named "tfplan" and get its root directory
  tfplan_path=$(find . -type f -name "tfplan" -exec dirname {} \; | head -n 1)

  if [[ -n "$tfplan_path" ]]; then
    # If a tfplan file is found
    cd "$tfplan_path" || { echo "Failed to change directory to $tfplan_path"; exit 1; }
    echo "Uninstalling Terraform resources..."
    terraform destroy -auto-approve -lock=false || { echo "Failed to destroy the Terraform resources."; exit 1; }
    return
  fi

  # If no tfplan file is found, search for a folder named ".databricks"
  databricks_path=$(find . -type d -name ".databricks" | head -n 1)

  if [[ -n "$databricks_path" ]]; then
    # If a .databricks folder is found
    cd "$databricks_path" || { echo "Failed to change directory to $databricks_path"; exit 1; }
    echo "Uninstalling Databricks resources..."

    command_output=$(databricks auth profiles)
    name_list=$(echo "$command_output" | awk '{print $1}' | tail -n +2)

    echo "Select an option:"
    options=()
    i=1
    while read -r name; do
      options+=("$name")
      echo "$i) $name"
      ((i++))
    done <<< "$name_list"

    read -r -p "Select the Profile used to installed SAT: " choice

    # Validate and process the selection
    if [[ "$choice" -gt 0 && "$choice" -le "${#options[@]}" ]]; then
      selected_name="${options[$((choice - 1))]}"
    else
      echo "Invalid selection. Please run the script again."
    fi

    databricks bundle destroy --auto-approve --force-lock -p $selected_name || { echo "Failed to destroy the Databricks resources."; exit 1; }
    cd ../
    rm -rf tmp .env
    return
  fi

  # If neither is found
  echo "No tfplan file or .databricks folder found."
}

install_sat(){
  clear

  local uninstall_available=0

  # Check uninstall
  if [[ -n $(find . -type f -name "tfplan" | head -n 1) || -n $(find . -type d -name ".databricks" | head -n 1) ]]; then
    uninstall_available=1
  fi

  echo "--------------------------------"
  echo "How do you want to install SAT?"
  echo "1) Via Terraform"
  echo "2) Via Terminal"
  if [[ $uninstall_available -eq 1 ]]; then
    echo "3) Uninstall"
  fi
  echo "--------------------------------"
  read -r -p "Please enter 1 or 2: " choice

  case $choice in
    1)
      terraform_install || { echo "Failed to install SAT via Terraform."; exit 1; }
      ;;
    2)
      shell_install || { echo "Failed to install SAT via Terminal."; exit 1; }
      ;;
    3)
      if [[ $uninstall_available -eq 1 ]]; then
        uninstall || { echo "Failed to uninstall SAT."; exit 1; }
      else
        echo "Uninstall option is not available."
      fi
      ;;
    *)
      echo "Invalid choice. Please run the script again and select 1 or 2."
      ;;
  esac

}

main(){
    if [[ -d "docs" || -d "images" || -n "$(find . -maxdepth 1 -name '*.md' -o -name 'LICENSE' -o -name 'NOTICE')" ]]; then
        install_sat || { echo "Failed to install SAT."; exit 1; }
    else
        if setup_sat; then
          ls
          cd "$INSTALLATION_DIR" || { echo "Failed to change directory to $INSTALLATION_DIR"; exit 1; }
          install_sat || { echo "Failed to install SAT."; exit 1; }
        fi
    fi
    exit 0
}

# ----------- Main Script -----------
main || { echo "Failed to run the main script."; exit 1; }
# ----------- Main Script -----------

