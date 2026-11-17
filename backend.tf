terraform {
backend "s3" {
bucket = "terraform-state"

key = "prod/main.tfstate"

endpoint = "http://172.26.67.48:9000"

region = "main"

skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true

force_path_style = true


}
}
