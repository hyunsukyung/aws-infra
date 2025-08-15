project       = "my-platform"
env           = "dev"
region        = "ap-northeast-2"
ecr_repo_name = "my-sample-api"
image_tag     = "latest"
desired_count = 2
cpu           = 256
memory        = 512
tags          = { owner = "you", "cost-center" = "portfolio", app = "my-platform" }
