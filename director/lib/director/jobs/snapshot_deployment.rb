module Bosh::Director
  module Jobs
    class SnapshotDeployment < BaseJob
      @queue = :normal

      attr_reader :deployment

      def initialize(deployment_name, options = {})
        @deployment = deployment_manager.find_by_name(deployment_name)
        @options = options
        @errors = 0
      end

      def deployment_manager
        @deployment_manager ||= Bosh::Director::Api::DeploymentManager.new
      end

      def perform
        logger.info("taking snapshot of: #{deployment.name}")
        deployment.job_instances.each do |instance|
          snapshot(instance)
        end

        msg = "snapshots of deployment '#{deployment.name}' created"
        msg += ", with #{@errors} failure(s)" unless @errors == 0
        msg
      end

      def snapshot(instance)
        logger.info("taking snapshot of: #{instance.job}/#{instance.index} (#{instance.vm.cid})")
        Bosh::Director::Api::SnapshotManager.take_snapshot(instance, @options)
      rescue Bosh::Clouds::CloudError
        @errors += 1
        logger.error("failed to take snapshot of: #{instance.job}/#{instance.index} (#{instance.vm.cid})")
        send_alert(instance)
      end

      ERROR = 3

      def send_alert(instance)
        nats = Bosh::Director::Config.nats
        payload = Yajl::Encoder.encode(
            {
                "id"         => 'director',
                "severity"   => ERROR,
                "title"      => "director - snapshot failure",
                "summary"    => "failed to snapshot #{instance.job}/#{instance.index}",
                "created_at" => Time.now.to_i
            }

        )

        nats.publish('hm.director.alert', payload)
      end
    end
  end
end

