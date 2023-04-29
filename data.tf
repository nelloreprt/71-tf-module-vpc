# to get >> peer_owner_id
data "aws_caller_identity" "current" {}


# using this we will get the data of default_vpc,
# but we need to specify default_vpc.id, we are specifying using variable block
data "aws_vpc" "default_vpc" {
  id = var.default_vpc_id
}