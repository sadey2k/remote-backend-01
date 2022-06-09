###################################
### Provider ###
###################################
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

###################################
### Variables ###
###################################
variable "aks_storage_rg" {
  default = "aks-storage-RG"
}

variable "aks_location" {
  default = "uk west"
}

variable "storage_account_name" {
  default = "aksstorage"
}

variable "storage_container_name" {
  default = "tfstate"
}

###################################
### random resources ###
###################################
resource "random_integer" "sa_num" {
  min = 1000
  max = 9999
}

###################################
### create resource group ###
###################################
resource "azurerm_resource_group" "aks_storage_rg" {
  name     = var.aks_storage_rg
  location = var.aks_location
}


###################################
### create storage account ###
###################################
resource "azurerm_storage_account" "aksstorage" {
  name                     = "${lower(var.storage_container_name)}${random_integer.sa_num.result}"
  resource_group_name      = azurerm_resource_group.aks_storage_rg.name
  location                 = var.aks_location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  depends_on = [
    azurerm_resource_group.aks_storage_rg
  ]

  tags = {
    environment = "Dev"
  }
}

###################################
### create container ### 
###################################
resource "azurerm_storage_container" "tfstate" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.aksstorage.name
  container_access_type = "private"
}

###################################
### create storage account sas token ###
###################################
data "azurerm_storage_account_sas" "state" {
  connection_string = azurerm_storage_account.aksstorage.primary_connection_string
  https_only        = true

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    file  = false
    queue = false
    table = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "17520h")

  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = true
    create  = true
    update  = false
    process = false
    filter  = false
    tag     = false
  }
}

resource "local_file" "post-config" {
  depends_on = [var.storage_container_name]

  filename = "${path.module}/backend-config.txt"
  content  = <<EOF
storage_account_name = "${azurerm_storage_account.aksstorage.name}"
container_name = var.storage_container_name
key = "terraform.tfstate"
sas_token = "${data.azurerm_storage_account_sas.state.sas}"
  EOF
}


###################################
### output file ###
###################################
output "aks_rg_name_location" {
  value = "${var.aks_storage_rg}-${var.aks_location}"
}

output "storage_account" {
  value = azurerm_storage_account.aksstorage.name
}

output "storage_container" {
  value = var.storage_container_name
}

output "shared_access_signature" {
  value = nonsensitive(data.azurerm_storage_account_sas.state.sas)
}
