# frozen_string_literal: true

require 'fugit'
require 'sidekiq'
require 'sidekiq/crond/job_keys'
require 'sidekiq/crond/support'

module Sidekiq
  module Crond
    # Class with cron job instance
    class Job
      # how long we would like to store informations about previous enqueues
      REMEMBER_THRESHOLD = 24 * 60 * 60
      LAST_ENQUEUE_TIME_FORMAT = '%Y-%m-%d %H:%M:%S %z'

      ENABLED_STATUS = 'enabled'
      DISABLED_STATUS = 'disabled'

      DEFAULT_QUEUE_NAME = 'default'

      attr_reader   :name, :cron, :description, :klass, :klass_const, :args, :queue,
                    :last_enqueue_time, :fetch_missing_args, :status

      def initialize(input_args = {})
        # stringify hash keys
        args = input_args.transform_keys(&:to_s)
        @fetch_missing_args = args.delete('fetch_missing_args')
        @fetch_missing_args = true if @fetch_missing_args.nil?

        @name = args['name']
        @cron = args['cron']
        @description = args['description'] if args['description']

        # get class from klass or class
        @klass = args['klass'] || args['class']
        @klass_const =
          begin
            Sidekiq::Crond::Support.constantize(klass.to_s)
          rescue NameError
            nil
          end

        # set status of job
        @status = args['status'] || status_from_redis

        # set last enqueue time - from args or from existing job
        @last_enqueue_time = if args['last_enqueue_time'] && !args['last_enqueue_time'].empty?
                               parse_enqueue_time(args['last_enqueue_time'])
                             else
                               last_enqueue_time_from_redis
                             end

        # get right arguments for job
        @args = args['args'].nil? ? [] : parse_args(args['args'])
        @args += [Time.now.to_f] if args['date_as_argument']

        # override queue if setted in config
        @queue = args['queue'] || nil
      end

      # crucial part of whole enquing job
      def should_enque?(time)
        Sidekiq.redis do |conn|
          enabled? &&
            not_past_scheduled_time?(time) &&
            not_enqueued_after?(time) &&
            conn.zadd(job_enqueued_key, formated_enqueue_time(time), formated_last_time(time))
        end
      end

      # remove previous informations about run times
      # this will clear redis and make sure that redis will
      # not overflow with memory
      def remove_previous_enques(time)
        Sidekiq.redis do |conn|
          conn.zremrangebyscore(job_enqueued_key, 0, "(#{(time.to_f - REMEMBER_THRESHOLD)}")
        end
      end

      # test if job should be enqued If yes add it to queue
      def test_and_enque_for_time!(time)
        # should this job be enqued?
        return unless should_enque?(time)

        enque!
        remove_previous_enques(time)
      end

      # enque cron job to queue
      def enque!(time = Time.now.utc)
        @last_enqueue_time = time.strftime(LAST_ENQUEUE_TIME_FORMAT)

        jid =
          if active_job?
            enqueue_active_job?.provider_job_id
          else
            enqueue_sidekiq_worker
          end

        save_last_enqueue_time
        add_jid_history(jid)
        Sidekiq.logger.debug "enqueued #{name}: #{args}, queue: #{queue}"
      end

      def active_job?
        defined?(ActiveJob::Base) && klass_const < ActiveJob::Base
      end

      def enqueue_active_job
        if queue.nil?
          klass_const.perform_later(*args)
        else
          klass_const.set(queue: queue).perform_later(*args)
        end
      end

      def enqueue_sidekiq_worker
        if queue.nil?
          klass_const.perform_async(*args)
        else
          klass_const.set(queue: queue).perform_async(*args)
        end
      end

      def disable!
        @status = DISABLED_STATUS
        save
      end

      def enable!
        @status = ENABLED_STATUS
        save
      end

      def enabled?
        status == ENABLED_STATUS
      end

      def disabled?
        !enabled?
      end

      def status_from_redis
        out = ENABLED_STATUS
        if fetch_missing_args
          Sidekiq.redis do |conn|
            status = conn.hget redis_key, 'status'
            out = status if status
          end
        end
        out
      end

      def last_enqueue_time_from_redis
        out = nil
        if fetch_missing_args
          Sidekiq.redis do |conn|
            out = begin
                    parse_enqueue_time(conn.hget(redis_key, 'last_enqueue_time'))
                  rescue StandardError
                    nil
                  end
          end
        end
        out
      end

      def jid_history_from_redis
        out =
          Sidekiq.redis do |conn|
            begin
              conn.lrange(jid_history_key, 0, -1)
            rescue StandardError
              []
            end
          end

        out.map do |jid_history_raw|
          Sidekiq.load_json(jid_history_raw)
        end
      end

      # export job data to hash
      def to_hash
        {
          name: @name,
          klass: @klass,
          cron: @cron,
          description: @description,
          args: @args.is_a?(String) ? @args : Sidekiq.dump_json(@args || []),
          status: @status,
          last_enqueue_time: @last_enqueue_time
        }
      end

      def errors
        @errors || []
      end

      def valid?
        # clear previous errors
        @errors = []

        @errors << "'name' must be set" if name.nil? || name.empty?
        if cron.nil? || cron.empty?
          @errors << "'cron' must be set"
        else
          begin
            parsed_cron
          rescue StandardError => e
            @errors << "'cron' -> #{cron.inspect} -> #{e.class}: #{e.message}"
          end
        end

        @errors << "'klass' (or class) must be set and exist" if klass_const.nil?
        errors.empty?
      end

      # add job to cron jobs
      # input:
      #   name: (string) - name of job
      #   cron: (string: '* * * * *' - cron specification when to run job
      #   class: (string|class) - which class to perform
      # optional input:
      #   queue: (string) - which queue to use for enquing (will override class queue)
      #   args: (array|hash|nil) - arguments for permorm method

      def save
        # if job is invalid return false
        return false unless valid?

        Sidekiq.redis do |conn|
          # add to set of all jobs
          conn.sadd Sidekiq::Crond::JobKeys.jobs_key, redis_key

          # add informations for this job!
          conn.hmset redis_key, *hash_to_redis(to_hash)

          # add information about last time! - don't enque right after scheduler poller starts!
          time = Time.now.utc
          unless conn.exists(job_enqueued_key)
            conn.zadd(job_enqueued_key, formated_enqueue_time(time), formated_last_time(time))
          end
        end
        Sidekiq.logger.info "Cron Jobs - add job with name: #{@name}"
      end

      def save_last_enqueue_time
        Sidekiq.redis do |conn|
          # update last enqueue time
          conn.hset redis_key, 'last_enqueue_time', last_enqueue_time
        end
      end

      def add_jid_history(jid)
        jid_history = {
          jid: jid,
          enqueued: last_enqueue_time
        }
        Sidekiq.redis do |conn|
          conn.lpush jid_history_key, Sidekiq.dump_json(jid_history)
          # keep only last "history_size" entries in a fifo manner
          conn.ltrim jid_history_key, 0, history_size
        end
      end

      # remove job from cron jobs by name
      def destroy
        Sidekiq.redis do |conn|
          # delete from set
          conn.srem Sidekiq::Crond::JobKeys.jobs_key, redis_key

          # delete runned timestamps
          conn.unlink job_enqueued_key

          # delete jid_history
          conn.unlink jid_history_key

          # delete main job
          conn.unlink redis_key
        end
        Sidekiq.logger.info "Cron Jobs - deleted job with name: #{name}"
      end

      # Parse cron specification '* * * * *' and returns
      # time when last run should be performed
      def last_time(time = Time.now.utc)
        parsed_cron.previous_time(time.utc).utc
      end

      def formated_enqueue_time(time = Time.now.utc)
        last_time(time).utc.to_f.to_s
      end

      def formated_last_time(time = Time.now.utc)
        last_time(time).utc.iso8601
      end

      def sort_name
        "#{enabled? ? 0 : 1}_#{name}".downcase
      end

      private

      def history_size
        @history_size ||= (Sidekiq.options[:cron_history_size] || 10).to_i - 1
      end

      def parsed_cron
        @parsed_cron ||= Fugit.parse_cron(cron)
      end

      def not_enqueued_after?(time)
        last_enqueue_time.nil? || last_enqueue_time.to_i < last_time(time).to_i
      end

      # Try parsing inbound args into an array.
      # args from Redis will be encoded JSON;
      # try to load JSON, then failover
      # to string array.
      def parse_args(args)
        case args
        when String
          begin
            Sidekiq.load_json(args)
          rescue JSON::ParserError
            [*args]   # cast to string array
          end
        when Hash
          [args]      # just put hash into array
        when Array
          args        # do nothing, already array
        else
          [*args]     # cast to string array
        end
      end

      def parse_enqueue_time(timestamp)
        DateTime.strptime(timestamp, LAST_ENQUEUE_TIME_FORMAT).to_time.utc
      rescue ArgumentError
        DateTime.parse(timestamp).to_time.utc
      end

      def not_past_scheduled_time?(current_time)
        last_cron_time = last_time(current_time)
        return false if (current_time.to_i - last_cron_time.to_i) > 60

        true
      end

      # Redis key for storing one cron job
      def redis_key
        Sidekiq::Crond::JobKeys.redis_key @name
      end

      # Redis key for storing one cron job run times
      # (when poller added job to queue)
      def job_enqueued_key
        Sidekiq::Crond::JobKeys.job_enqueued_key @name
      end

      def jid_history_key
        Sidekiq::Crond::JobKeys.jid_history_key @name
      end

      # Give Hash
      # returns array for using it for redis.hmset
      def hash_to_redis(hash)
        hash.to_a.flatten
      end
    end
  end
end
