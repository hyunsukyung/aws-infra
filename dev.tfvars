project           = "my-platform"
env               = "dev"
region            = "ap-northeast-2"
ecr_repo_name     = "my-sample-api"
image_tag         = "latest"
desired_count     = 2
cpu               = 256
memory            = 512
tags              = { owner = "you", "cost-center" = "portfolio", app = "my-platform" }
db_engine         = "mysql"
db_engine_version = "8.0.42"
db_name           = "appdb"
db_username       = "appuser"
db_password       = "ChangeMeStrong"
db_port           = 3306
//domain_name = "example.com"
//subdomain = "app"
yourls_admin_pass = "StrongPassword123!"

enable_multi_az            = false
enable_pi                  = false
enable_enhanced_monitoring = false
export_slow_logs           = false
backup_retention_days      = 3
deletion_protection        = false
skip_final_snapshot        = true
