# frozen_string_literal: true

module Sidekiq
  module Crond
    # Class with cron job redis keys
    class JobKeys
      REDIS_KEY_PREFIX = 'cron_job'

      class << self
        # Redis key for set of all cron jobs
        def jobs_key
          'crond_jobs'
        end

        # Redis key for storing one cron job
        def redis_key(name)
          "#{REDIS_KEY_PREFIX}:#{name}"
        end

        # Redis key for storing one cron job run times
        # (when poller added job to queue)
        def job_enqueued_key(name)
          "#{REDIS_KEY_PREFIX}:#{name}:enqueued"
        end

        def jid_history_key(name)
          "#{REDIS_KEY_PREFIX}:#{name}:jid_history"
        end
      end
    end
  end
end
