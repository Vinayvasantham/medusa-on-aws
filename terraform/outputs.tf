output "rds_endpoint" {
  description = "The endpoint of the PostgreSQL RDS instance"
  value       = aws_db_instance.postgres.endpoint
}
