resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.medusa-project}-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.medusa-project}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.medusa-project}-public-b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.medusa-project}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.medusa-project}-route-table"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


resource "aws_security_group" "medusa_sg" {
  name        = "${var.medusa-project}-sg"
  description = "Allow 9000 and Postgres"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Medusa HTTP"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.medusa-project}-sg"
  }
}


resource "aws_db_subnet_group" "medusa_db_subnet" {
  name       = "${var.medusa-project}-db-subnet-group"
  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "${var.medusa-project}-db-subnet"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "${var.medusa-project}-db"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "medusadb"
  username                = "medusa_user"
  password             = var.db_password
  publicly_accessible     = true
  vpc_security_group_ids  = [aws_security_group.medusa_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.medusa_db_subnet.name
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

resource "aws_ecs_cluster" "main" {
  name = "${var.medusa-project}-cluster"
}

resource "aws_ecr_repository" "medusa_repo" {
  name = "${var.medusa-project}-repo"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "${var.medusa-project}-ecr"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.medusa-project}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "medusa_task" {
  family                   = "${var.medusa-project}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "medusa",
      image     = "${aws_ecr_repository.medusa_repo.repository_url}:latest",
      portMappings = [
        {
          containerPort = 9000,
          hostPort      = 9000
        }
      ],
      environment = [
        {
          name  = "NODE_ENV",
          value = "production"
        },
        {
          name  = "PORT",
          value = "9000"
        },
        {
          name  = "DATABASE_URL",
          value = "postgres://medusa_user:${var.db_password}@${aws_db_instance.postgres.address}:5432/medusa_my_medusa_store?ssl=true&sslmode=require&rejectUnauthorized=false"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "medusa_service" {
  name            = "${var.medusa-project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.medusa_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_a.id]
    security_groups = [aws_security_group.medusa_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_execution_policy]
}


# resource "aws_vpc" "main" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_support   = true
#   enable_dns_hostnames = true
#   tags = {
#     Name = "${var.project_name}-vpc"
#   }
# }

# resource "aws_subnet" "public_a" {
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = "10.0.1.0/24"
#   availability_zone = "${var.region}a"
#   map_public_ip_on_launch = true
#   tags = {
#     Name = "${var.project_name}-public-a"
#   }
# }

# resource "aws_internet_gateway" "igw" {
#   vpc_id = aws_vpc.main.id
#   tags = {
#     Name = "${var.project_name}-igw"
#   }
# }

# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.igw.id
#   }
#   tags = {
#     Name = "${var.project_name}-route-table"
#   }
# }

# resource "aws_route_table_association" "a" {
#   subnet_id      = aws_subnet.public_a.id
#   route_table_id = aws_route_table.public.id
# }

# resource "aws_ecs_cluster" "main" {
#   name = "${var.project_name}-cluster"
# }

# resource "aws_ecr_repository" "medusa_repo" {
#   name = "${var.project_name}-repo"
#   image_scanning_configuration {
#     scan_on_push = true
#   }
#   tags = {
#     Name = "${var.project_name}-ecr"
#   }
# }


# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "${var.project_name}-ecs-execution-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = "sts:AssumeRole",
#         Effect = "Allow",
#         Principal = {
#           Service = "ecs-tasks.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# resource "aws_ecs_task_definition" "medusa_task" {
#   family                   = "${var.project_name}-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "512"
#   memory                   = "1024"
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

#   container_definitions = jsonencode([
#     {
#       name      = "medusa"
#       image     = "${aws_ecr_repository.medusa_repo.repository_url}:latest"
#       portMappings = [
#         {
#           containerPort = 9000
#           hostPort      = 9000
#         }
#       ],
#       environment = [
#         {
#           name  = "NODE_ENV"
#           value = "production"
#         },
#         {
#           name  = "PORT"
#           value = "9000"
#         }
#       ]
#     }
#   ])
# }

# resource "aws_security_group" "medusa_sg" {
#   name        = "${var.project_name}-sg"
#   description = "Allow 9000"
#   vpc_id      = aws_vpc.main.id

#   ingress {
#     description = "Allow Medusa HTTP"
#     from_port   = 9000
#     to_port     = 9000
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "${var.project_name}-sg"
#   }
# }

# resource "aws_ecs_service" "medusa_service" {
#   name            = "${var.project_name}-service"
#   cluster         = aws_ecs_cluster.main.id
#   task_definition = aws_ecs_task_definition.medusa_task.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"

#   network_configuration {
#     subnets         = [aws_subnet.public_a.id]
#     security_groups = [aws_security_group.medusa_sg.id]
#     assign_public_ip = true
#   }

#   depends_on = [aws_iam_role_policy_attachment.ecs_execution_policy]
# }

