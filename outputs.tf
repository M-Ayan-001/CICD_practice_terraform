output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.createALB.dns_name
}

output "alb_arn" {
  description = "The ARN of the load balancer"
  value       = aws_lb.createALB.arn
}

output "alb_id" {
  description = "The ID of the load balancer"
  value       = aws_lb.createALB.id
}
