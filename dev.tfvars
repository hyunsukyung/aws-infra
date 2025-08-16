project       = "my-platform"
env           = "dev"
region        = "ap-northeast-2"
ecr_repo_name = "my-sample-api"
image_tag     = "latest"
desired_count = 2
cpu           = 256
memory        = 512
tags          = { owner = "you", "cost-center" = "portfolio", app = "my-platform" }
db_engine = "mysql"
db_engine_version = "8.0.42"
db_name = "appdb"
db_username = "appuser"
db_password = "ChangeMeStrong"
db_port = 3306
//domain_name = "example.com"
//subdomain = "app"
