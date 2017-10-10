CloudFormation do
  stack_name = "#{env['name']}-#{env['tier']}"

  Parameter(:RDSPostgresPassword) do
    Description 'MasterPassword for RDS Postgres DB Instance.'
    ConstraintDescription 'Must be 32 characters.'
    NoEcho true
    MaxLength 32
    MinLength 32
  end

  ###
  ### VPC
  ###
  EC2_VPC(:VPC) do
    CidrBlock vpc['cidr']
    EnableDnsSupport true
    EnableDnsHostnames true

    Tag do
      Key 'Name'
      Value "#{stack_name}-vpc"
    end
  end

  EC2_InternetGateway(:InternetGateway) do
    Tag do
      Key 'Name'
      Value "#{stack_name}-igw"
    end
  end

  EC2_VPCGatewayAttachment(:InternetGatewayAttachment) do
    VpcId Ref(:VPC)
    InternetGatewayId Ref(:InternetGateway)
  end

  EC2_RouteTable(:PublicRouteTable) do
    VpcId Ref(:VPC)

    Tag do
      Key 'Name'
      Value "#{stack_name}-public-routetable"
    end
  end

  EC2_Route(:PublicRouteTableInternetGatewayRoute) do
    DestinationCidrBlock '0.0.0.0/0'
    GatewayId Ref(:InternetGateway)
    RouteTableId Ref(:PublicRouteTable)
  end

  # x:  cidr block
  # a:  vpc number
  # p:  public (0) or private (1)
  # z:  availability zone
  # i:  instance
  #
  # xxxxxxxx.vvvvvvvv.pzzziiii.iiiiiiii
  # 00001010.00000000.00000000.00000000
  # 00001010.11111111.11111111.11111111

  public_subnets = []
  private_subnets = []

  vpc['subnet'].each do |subnet_type, subnet_conf|
    subnet_conf.each.with_index do |subnet, idx|
      num = idx + 1

      subnet_name = "#{subnet_type.capitalize}Subnet#{num}"

      EC2_Subnet(subnet_name) do
        VpcId Ref(:VPC)
        CidrBlock subnet['cidr']
        AvailabilityZone FnSub("${AWS::Region}#{subnet['zone']}")

        Tag do
          Key 'Name'
          Value "#{stack_name}-#{subnet_type.downcase}-subnet-#{num}"
        end
      end

      nat_gateway_name = "NatGateway#{num}"

      if subnet_type == 'public'
        public_subnets.push(subnet_name)

        EC2_SubnetRouteTableAssociation("#{subnet_name}PublicRouteTableAssociation") do
          RouteTableId Ref(:PublicRouteTable)
          SubnetId Ref(subnet_name)
        end

        nat_eip_name = "NatGateway#{num}EIP"

        EC2_EIP(nat_eip_name) do
          DependsOn :VPC

          Domain 'vpc'
        end

        EC2_NatGateway(nat_gateway_name) do
          DependsOn :InternetGateway

          AllocationId FnGetAtt(nat_eip_name, :AllocationId)
          SubnetId Ref(subnet_name)
        end
      end

      if subnet_type == 'private'
        private_subnets.push(subnet_name)

        route_table_name = "PrivateRouteTable#{num}"

        EC2_RouteTable(route_table_name) do
          VpcId Ref(:VPC)

          Tag do
            Key 'Name'
            Value "#{stack_name}-private-routetable-#{num}"
          end
        end

        EC2_Route("#{route_table_name}#{nat_gateway_name}Route") do
          DestinationCidrBlock '0.0.0.0/0'
          NatGatewayId Ref(nat_gateway_name)
          RouteTableId Ref(route_table_name)
        end

        EC2_SubnetRouteTableAssociation("#{subnet_name}#{route_table_name}Association") do
          RouteTableId Ref(route_table_name)
          SubnetId Ref(subnet_name)
        end
      end
    end
  end

  ###
  ### RDS Postgres
  ###
  RDS_DBSubnetGroup(:RDSPostgresSubnetGroup) do
    SubnetIds private_subnets.map {|n| Ref(n)}

    DBSubnetGroupDescription "RDS Postgres Subnet Group for #{stack_name}"
  end

  EC2_SecurityGroup(:RDSPostgresSecurityGroup) do
    GroupName "#{stack_name}-rds-postgres-security-group"
    GroupDescription "RDS Postgres Security Group for #{stack_name}"
    VpcId Ref(:VPC)
    SecurityGroupIngress([{
      CidrIp: vpc['cidr'],
      IpProtocol: 'tcp',
      FromPort: 5432,
      ToPort: 5432
    }])
  end

  RDS_DBInstance(:RDSPostgresDBInstance) do
    DeletionPolicy 'Snapshot'

    StorageType rds['storage_type'] || 'gp2'
    StorageEncrypted rds['storage_encrypted'] || false
    AllocatedStorage rds['allocated_storage']
    DBInstanceClass rds['db_instance_class']
    DBInstanceIdentifier "#{stack_name}-rds-postgres-dbinstance"
    VPCSecurityGroups [Ref(:RDSPostgresSecurityGroup)]
    DBSubnetGroupName Ref(:RDSPostgresSubnetGroup)
    MultiAZ rds['multi_az'] || false
    Engine 'postgres'
    DBName 'postgres'
    MasterUsername 'postgres'
    MasterUserPassword Ref(:RDSPostgresPassword)
    MonitoringInterval rds['monitoring_interval'] || 0
    MonitoringRoleArn FnSub('arn:aws:iam::${AWS::AccountId}:role/RDSEnhancedMonitoring')

    if rds['storage_type'] == 'io1'
      Iops rds['iops']
    end
  end

  ###
  ### Jump Host
  ###
  EC2_SecurityGroup(:JumpHostSecurityGroup) do
    GroupName "#{stack_name}-jump-host-security-group"
    GroupDescription "Jump Host Security Group for #{stack_name}"
    VpcId Ref(:VPC)
    SecurityGroupIngress [{
      CidrIp: '0.0.0.0/0',
      IpProtocol: 'tcp',
      FromPort: 22,
      ToPort: 22
    }]
  end

  EC2_EIP(:JumpHostEIP) do
    DependsOn :VPC

    Domain 'vpc'
  end

  EC2_Instance(:JumpHostInstance) do
    DependsOn public_subnets.first

    Tenancy 'default'
    ImageId ec2['jump']['ami']
    InstanceInitiatedShutdownBehavior 'stop'
    InstanceType ec2['jump']['instance_type']
    KeyName ec2['jump']['key_name']
    Monitoring ec2['jump']['monitoring'] || false
    SecurityGroupIds [Ref(:JumpHostSecurityGroup)]
    UserData FnBase64('touch done.txt')
    SubnetId Ref(public_subnets.first)
    DisableApiTermination true

    BlockDeviceMappings([{
      DeviceName: '/dev/xvda',
      VirtualName: "#{stack_name}-jump-host-volume",
      Ebs: {
        VolumeSize: (ec2['volume_size'] || 8),
        DeleteOnTermination: false
      }
    }])

    Tag do
      Key 'Name'
      Value "#{stack_name}-jump-host-instance"
    end
  end

  EC2_EIPAssociation(:JumpHostInstanceEIPAssociation) do
    InstanceId Ref(:JumpHostInstance)
    EIP Ref(:JumpHostEIP)
  end

  # Learn more about instance recovery/reboot via cloud watch monitoring here:
  # http://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/iam-access-control-overview-cw.html
  CloudWatch_Alarm(:JumpHostInstanceAutoRecoveryAlarm) do
    AlarmName "#{stack_name}-jump-host-instance-auto-recovery-alarm"
    AlarmDescription "Enables Auto Recovery for Jump Host Instance for #{stack_name}"
    Namespace 'AWS/EC2'
    MetricName 'StatusCheckFailed_System'
    Period 60
    EvaluationPeriods 5
    Statistic 'Minimum'
    Threshold 0
    ComparisonOperator 'GreaterThanThreshold'
    AlarmActions [FnSub('arn:aws:automate:${AWS::Region}:ec2:recover')]
    Dimensions [{Name: 'InstanceId', Value: Ref(:JumpHostInstance)}]
  end

  CloudWatch_Alarm(:JumpHostInstanceAutoRebootAlarm) do
    AlarmName "#{stack_name}-jump-host-instance-auto-reboot-alarm"
    AlarmDescription "Enables Auto Reboot for Jump Host Instance for #{stack_name}"
    Namespace 'AWS/EC2'
    MetricName 'StatusCheckFailed_Instance'
    Period 60
    EvaluationPeriods 5
    Statistic 'Minimum'
    Threshold 0
    ComparisonOperator 'GreaterThanThreshold'
    AlarmActions [FnSub('arn:aws:swf:${AWS::Region}:${AWS::AccountId}:action/actions/AWS_EC2.InstanceId.Reboot/1.0')]
    Dimensions [{Name: 'InstanceId', Value: Ref(:JumpHostInstance)}]
  end

  jump_host_dns_name = "jump.#{stack_name}.#{r53['domain_name']}"

  Route53_RecordSet(:JumpHostDNSRecordSet) do
    HostedZoneId r53['zone_id']
    Name "#{jump_host_dns_name}."
    Type "A"
    TTL 600
    ResourceRecords([
      Ref(:JumpHostEIP)
    ])
  end

  ###
  ### Application ELB
  ###
  EC2_SecurityGroup(:ELBSecurityGroup) do
    GroupName "#{stack_name}-elb-security-group"
    GroupDescription "ELB Security Group for #{stack_name}"
    VpcId Ref(:VPC)
    SecurityGroupIngress([
      {
        CidrIp: '0.0.0.0/0',
        IpProtocol: 'tcp',
        FromPort: 80,
        ToPort: 80
      },
      {
        CidrIp: '0.0.0.0/0',
        IpProtocol: 'tcp',
        FromPort: 443,
        ToPort: 443
      },
    ])
  end

  ###
  ### Application Instance Group
  ###
  EC2_SecurityGroup(:ApplicationSecurityGroup) do
    GroupName "#{stack_name}-application-security-group"
    GroupDescription "Application Security Group for #{stack_name}"
    VpcId Ref(:VPC)
    SecurityGroupIngress([
      {
        CidrIp: '0.0.0.0/0',
        IpProtocol: 'tcp',
        FromPort: 80,
        ToPort: 80
      },
      {
        CidrIp: '0.0.0.0/0',
        IpProtocol: 'tcp',
        FromPort: 443,
        ToPort: 443
      },
      {
        SourceSecurityGroupId: Ref(:JumpHostSecurityGroup),
        IpProtocol: 'tcp',
        FromPort: 22,
        ToPort: 22
      },
    ])
  end

  Output(:RDSPostgresEndpointAddress) do
    Description "RDS Postgres Endpoint Address for #{stack_name}"
    Value FnGetAtt(:RDSPostgresDBInstance, 'Endpoint.Address')
  end

  Output(:RDSPostgresEndpointPort) do
    Description "RDS Postgres Endpoint Port for #{stack_name}"
    Value FnGetAtt(:RDSPostgresDBInstance, 'Endpoint.Port')
  end

  Output(:JumpHostKeyName) do
    Description "Jump Host Key Name for #{stack_name}"
    Value ec2['jump']['key_name']
  end

  Output(:JumpHostEIP) do
    Description "Jump Host IP Address for #{stack_name}"
    Value Ref(:JumpHostEIP)
  end

  Output(:JumpHostDNSAddress) do
    Description "Jump Host DNS Address for #{stack_name}"
    Value jump_host_dns_name
  end
end
