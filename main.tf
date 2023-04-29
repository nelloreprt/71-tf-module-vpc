resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = merge(var.tags,
    { Name = "${var.env}-main" })
}


# Public subnets we are creating public_subnet in az-1 & az-2, for high availability
resource "aws_subnet" "public_subnets"{
  vpc_id     = aws_vpc.main.id
  tags = merge(var.tags,
    { Name = "${var.env}-each.valu.name" })

  for_each = var.public_subnets
  cidr_block = each.value.cidr_block
  availability_zone = each.value.availability_zone

}

# Private subnets we are creating private_subnet in az-1 & az-2, for high availability
resource "aws_subnet" "private_subnets" {
  vpc_id     = aws_vpc.main.id
  tags = merge(var.tags,
    { Name = "${var.env}-each.valu.name" })

  for_each = var.private_subnets
  cidr_block = each.value.cidr_block
  availability_zone = each.value.availability_zone

}

# Rule: every subnet shall have a ROUTE_TABLE
# Public Route Table
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.main.id
  tags = merge(var.tags,
    { Name = "${var.env}-each.valu.name" })

  for_each = var.public_subnets

#igw-step-2 internet gateway should go as a ROUTE to PUBLIC_SUBNET and not to private_subnet
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id

  route {
    # retreiving CIDR block of the default_vpc using data_source_block
    cidr_block = data.aws_vpc.default_vpc.cidr_block     # enter cidr range of default_vpc              # routing to default_vpc
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
    }
}

# ////////////////////////////////////////////////////////////////////////////////////
# Private Route Table
resource "aws_route_table" "private-route-table" {
 vpc_id = aws_vpc.main.id
 tags = merge(var.tags,
   { Name = "${var.env}-each.valu.name" })

 for_each = var.private_subnets

  # split("-", "web-az1")[1]
  # index no     0   1

# 01:10:00
# after nat-gateway creation,
# we have to give that information to pvt_route_table (ROUTE)
# according to architecture diagram, in every public_subnet one nat_gateway is placed,
# there are 2 public_subnets in 2-AZ,, so we require 2-nat_gateways
# this nat_gateway shall be connected to web_layer(az-1) and web_layer(az-2) only
# and not to app_layer and not to db_layer
# if we go with each.value["name"] >> then the names of public_subnet are (public-az1 , public-az2)
# where as the names of private_subnets(of web)  are (web-az1 , web-az2)
# ==============================================================================
# so this is a PRIVATE_SUBNET in AZ-1 of WEB (i.e web-az-1) ,
# but we need az-1 nat_gateway which is created in public az-1

# similarly >> (web-az-2)
# in a PRIVATE_SUBNET in AZ-2 of WEB (i.e web-az-2) ,
# but we need nat_gateway of az-2 which is created in public az-2

# so we take help of SPLIT_function
# nat_gateway_id = aws_nat_gateway.nat-gateways[public-split("-", each.value["name"])[1]].id
# from private_subnets iteration, using for_each we will pick the name using each.value["name"]
# and immediately we will use SPLIT_function with Index_number[1] and we will further pick only-az1
# now to the az1 we will add public,. so the result is >> public-az1  for the first iteration
# and public-az2  for the Second iteration
# ==============================================================================

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gateways[public-split("-", each.value["name"])[1]].id
# final value >>                 aws_nat_gateway.nat-gateways[public-az1].id
}

  route {
    # retreiving CIDR block of the default_vpc using data_source_block
    cidr_block = data.aws_vpc.default_vpc.cidr_block                   # routing to default_vpc
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }
}
# ///////////////////////////////////////////////////////////////////////////////////////////


# associate route table to appropriate subnets (public)
resource "aws_route_table_association" "public_association" {
  for_each = var.public_subnets

  subnet_id      = aws_subnet.public_subnets[each.value[name]].id
  route_table_id = aws_route_table.public-route-table[each.value[name]].id
}


# associate route table to appropriate subnets (private)
resource "aws_route_table_association" "private_association" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private_subnets[each.value[name]].id
  route_table_id = aws_route_table.private-route-table[each.value[name]].id
}

# igw-step-1 Adding Internet Gateway, for a VPC only ONE INTERNET GATEWAY is allowed
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags,
    { Name = "${var.env}-igw"})
}


# we are going to create 2-nat gateways, one each on TWO 2-Public subnets
# then we are going to attach the natgateway to appropriate AZ's
# after nat-gateway creation, we have to give that information to pvt_route_table (ROUTE)
resource "aws_nat_gateway" "nat-gateways" {
  for_each = var.public_subnets
  allocation_id = aws_eip.nat[each.value["name"]].id
  subnet_id     =  aws_subnet.private_subnets[each.value[name]].id

  tags = merge(var.tags,
    { Name = "${var.env}-each.valu.name" })
  }



  #  we need to take Elastic_ip,
  # the number of eip will depend on the number of public_subnet or number of nat_gateway
  # so that nat_gateway can take one internet connection with the eip and
  # it is going to distribute the traffic
resource "aws_eip" "nat" {
    for_each = var.public_subnets
    vpc      = true
  }



# Peering Connection
resource "aws_vpc_peering_connection" "peer" {
  peer_owner_id = data.aws_caller_identity.current.id    # // 1 // peer_owner >> the target vpc, to which we want to connect, for which we have to give target aws_account_id_details
  peer_vpc_id   = var.default_vpc_id # to_vpc            # // 2 // TO >> Target vpc_id to which you want to connect >> in our case it is the default vpc_id
  vpc_id        = aws_vpc.main.id    # from_vpc          # // 3 // FROM dev-vpc_id
  auto_accept = "yes"                                    # // 4 // Target vpc has to accept the request manually, since both target_vpc and source_vpc are in same account, we use auto_accept

  tags = merge(var.tags,
    { Name = "${var.env}-vpc-peering" })
}
# /////////////////////////////////////////////////////////////////////////////////////
# on the other side we need to add route to the default_vpc
# Route to default_vpc for the peering to work

  // to the Default VPC there will be default_Route_Table, we need to add route to it there
  // we will take the help of data.tf


  // adding entry in the default_route table to support DEFAULT-VPC
  resource "aws_route" "route" {
    // 1 // when you create a VPC you will get by default ONE ROUTE_TABLE
    route_table_id            = var.default_route_table   # enter default_Route_table_Id

    // 2 // default_vpc CIDR_range
    // " new_vpc cidr range details " we are entering inside the default_route_table using ROUTE
    destination_cidr_block    = var.vpc_cidr  # enter cidr range of main_vpc

    // 3 // how to reach to default_vpc >> using Peering connection
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id

  }