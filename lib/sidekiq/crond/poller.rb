# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/crond'
require 'sidekiq/scheduled'

module Sidekiq
  module Crond
    POLL_INTERVAL = 30

    # The Poller checks Redis every N seconds for sheduled cron jobs
    class Poller < Sidekiq::Scheduled::Poller
      def enqueue
        time = Time.now.utc
        Sidekiq::Crond::Jobs.all.each do |job|
          enqueue_job(job, time)
        end
      rescue StandardError => e
        # Most likely a problem with redis networking.
        # Punt and try again at the next interval
        Sidekiq.logger.error e.message
        Sidekiq.logger.error e.backtrace.first
        handle_exception(e) if respond_to?(:handle_exception)
      end

      private

      def enqueue_job(job, time = Time.now.utc)
        job.test_and_enque_for_time!(time) if job&.valid?
      rescue StandardError => e
        # problem somewhere in one job
        Sidekiq.logger.error "CRON JOB: #{e.message}"
        Sidekiq.logger.error "CRON JOB: #{e.backtrace.first}"
        handle_exception(e) if respond_to?(:handle_exception)
      end

      def poll_interval_average
        Sidekiq.options[:poll_interval] || POLL_INTERVAL
      end
    end
  end
end
