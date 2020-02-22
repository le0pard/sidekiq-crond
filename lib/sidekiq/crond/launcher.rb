# frozen_string_literal: true

# require  Sidekiq original launcher
require 'sidekiq/launcher'

# require cron poller
require 'sidekiq/crond/poller'

# For Cron we need to add some methods to Launcher
# so look at the code bellow.
#
# we are creating new cron poller instance and
# adding start and stop commands to launcher
module Sidekiq
  module Crond
    # Module inject into sidekiq launcher
    module Launcher
      # Add cron poller to launcher
      attr_reader :crond_poller

      # add cron poller and execute normal initialize of Sidekiq launcher
      def initialize(options)
        @crond_poller = Sidekiq::Crond::Poller.new
        super(options)
      end

      # execute normal run of launcher and run cron poller
      def run
        super
        crond_poller.start
      end

      # execute normal quiet of launcher and quiet cron poller
      def quiet
        crond_poller.terminate
        super
      end

      # execute normal stop of launcher and stop cron poller
      def stop
        crond_poller.terminate
        super
      end
    end
  end
end

::Sidekiq::Launcher.prepend(Sidekiq::Crond::Launcher)
