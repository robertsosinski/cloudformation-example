CloudFormation do
  # Required for Cloud Watch to perform Reboot/Stop/Termination Actions
  # NOTE: DO NOT change 'RoleName', the exact name must be 'EC2ActionsAccess'
  IAM_Role(:EC2ActionsAccessRole) do
    RoleName 'EC2ActionsAccess'
    ManagedPolicyArns ['arn:aws:iam::aws:policy/CloudWatchActionsEC2Access']
    Path '/actions/'

    AssumeRolePolicyDocument({
      Version: '2012-10-17',
      Statement: [
        Effect: 'Allow',
        Action: 'sts:AssumeRole',
        Principal: {
          Service: 'swf.amazonaws.com'
        }
      ]
    })
  end

  # Required for RDS to send enhanded OS level metrics to Cloud Watch
  IAM_Role(:RDSEnhancedMonitoringRole) do
    RoleName 'RDSEnhancedMonitoring'
    ManagedPolicyArns ['arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole']
    Path '/'

    AssumeRolePolicyDocument({
      Version: '2012-10-17',
      Statement: [
        Effect: 'Allow',
        Action: 'sts:AssumeRole',
        Principal: {
          Service: 'monitoring.rds.amazonaws.com'
        }
      ]
    })
  end

  Output(:EC2ActionsAccessRoleName) do
    Description "IAM Role Name for EC2ActionsAccess Cloud Watch Policy"
    Value Ref(:EC2ActionsAccessRole)
    Export 'account-ec2-actions-access-role-name'
  end

  Output(:EC2ActionsAccessRoleArn) do
    Description "IAM Role Arn for EC2ActionsAccess Cloud Watch Policy"
    Value FnGetAtt(:EC2ActionsAccessRole, 'Arn')
    Export 'account-ec2-actions-access-role-arn'
  end

  Output(:RDSEnhancedMonitoringRoleName) do
    Description "IAM Role Name for EC2ActionsAccess Cloud Watch Policy"
    Value Ref(:RDSEnhancedMonitoringRole)
    Export 'account-rds-enhanced-monitoring-role-name'
  end

  Output(:RDSEnhancedMonitoringRoleArn) do
    Description "IAM Role Arn for EC2ActionsAccess Cloud Watch Policy"
    Value FnGetAtt(:RDSEnhancedMonitoringRole, 'Arn')
    Export 'account-rds-enhanced-monitoring-role-arn'
  end
end
