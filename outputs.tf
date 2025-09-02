output "alb_dns_name" { value = aws_lb.app.dns_name }
output "ecr_repo_url" { value = aws_ecr_repository.app.repository_url }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "cloudfront_domian" {
  description = "CloudFront 기본 도메인 (HTTPS 지원)"
  value       = aws_cloudfront_distribution.alb_front.domain_name
}
