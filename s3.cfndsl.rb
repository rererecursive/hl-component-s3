CloudFormation do

  buckets.each do |bucket, config|

    safe_bucket_name = bucket.capitalize.gsub('_','').gsub('-','')
    bucket_type = config.has_key?('type') ? config['type'] : 'default'
    bucket_name = config.has_key?('bucket_name') ? config['bucket_name'] : bucket

    notification_configurations = {}
    if config.has_key?('notifications')
        if config['notifications'].has_key?('lambda')
            notification_configurations['LambdaConfigurations'] = []
            config['notifications']['lambda'].each do |values|
                lambda_config = {}
                lambda_config['Function'] = values['function']
                lambda_config['Event'] = values['event']
                notification_configurations['LambdaConfigurations'] << lambda_config
            end
        end
    end


    if bucket_type == 'create_if_not_exists'
      Resource("#{safe_bucket_name}") do
        Type 'Custom::S3BucketCreateOnly'
        Property 'ServiceToken',FnGetAtt('S3BucketCreateOnlyCR','Arn')
        Property 'Region', Ref('AWS::Region')
        Property 'BucketName', FnSub(bucket_name)
      end
    else
      S3_Bucket("#{safe_bucket_name}") do
        BucketName FnSub(bucket_name)
        Tags([
          { Key: 'Name', Value: FnSub("${EnvironmentName}-#{bucket}") },
          { Key: 'Environment', Value: Ref("EnvironmentName") },
          { Key: 'EnvironmentType', Value: Ref("EnvironmentType") }
        ])
        NotificationConfiguration notification_configurations unless notification_configurations.empty?
        LifecycleConfiguration({ Rules: config['lifecycle_rules'] }) if config.has_key?('lifecycle_rules')
      end
    end

    if config.has_key?('ssm_parameter')
      SSM_Parameter("#{safe_bucket_name}Parameter") do
        Name FnSub(config['ssm_parameter'])
        Type 'String'
        Value Ref(safe_bucket_name)
      end
    end

    Output(safe_bucket_name) { Value(Ref(safe_bucket_name)) }
    Output(safe_bucket_name + 'DomainName') { Value(FnGetAtt(safe_bucket_name, 'DomainName')) }


    if config.has_key?('bucket-policy')
        policy_document = {}
        policy_document["Statement"] = []

        config['bucket-policy'].each do |sid, statement_config|
            statement = {}
            statement["Sid"] = sid
            statement['Effect'] = statement_config.has_key?('effect') ? statement_config['effect'] : "Allow"
            statement['Principal'] = statement_config.has_key?('principal') ? statement_config['principal'] : {AWS: FnSub("arn:aws:iam::${AWS::AccountId}:root")}
            statement['Resource'] = statement_config.has_key?('resource') ? statement_config['resource'] : [FnJoin("",["arn:aws:s3:::", Ref(safe_bucket_name)]), FnJoin("",["arn:aws:s3:::", Ref(safe_bucket_name), "/*"])]
            statement['Action'] = statement_config.has_key?('actions') ? statement_config['actions'] : ["s3:*"]
            statement['Condition'] = statement_config['conditions'] if statement_config.has_key?('conditions')
            policy_document["Statement"] << statement
        end

        S3_BucketPolicy("#{safe_bucket_name}Policy") do
            Bucket Ref(safe_bucket_name)
            PolicyDocument policy_document
        end
    end


  end if defined? buckets

end