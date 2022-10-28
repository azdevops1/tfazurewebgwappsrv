terraform {

  required_version = ">=0.14.9"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.9.0"
    }
  }
}

provider "azurerm" {
    features {}
}