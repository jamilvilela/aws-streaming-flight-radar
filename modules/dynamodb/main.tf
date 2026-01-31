resource "aws_dynamodb_table" "table" {
  for_each     = toset(var.tables)
  name         = "${var.project_name}-${each.key}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

output "table_arns" {
  value = {
    for table in var.tables :
    table => aws_dynamodb_table.table[table].arn
  }
}