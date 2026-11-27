output "schedule_group_name" {
  description = "Schedule group of the stop and start schedules."
  value       = aws_scheduler_schedule_group.this.name
}

output "schedule_names" {
  description = "Schedules by action and cluster (start-<id>, stop-<id>)."
  value       = sort(keys(aws_scheduler_schedule.this))
}
