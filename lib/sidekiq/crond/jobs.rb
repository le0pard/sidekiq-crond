# frozen_string_literal: true

require 'fugit'
require 'sidekiq'
require 'sidekiq/util'
require 'sidekiq/crond/job'
require 'sidekiq/crond/job_keys'
require 'sidekiq/crond/support'

module Sidekiq
  module Crond
    # Class with cron jobs
    class Jobs
      class << self
        # load cron jobs from Hash
        # input structure should look like:
        # {
        #   'name_of_job' => {
        #     'class'       => 'MyClass',
        #     'cron'        => '1 * * * *',
        #     'args'        => '(OPTIONAL) [Array or Hash]',
        #     'description' => '(OPTIONAL) Description of job'
        #   },
        #   'My super iber cool job' => {
        #     'class' => 'SecondClass',
        #     'cron'  => '*/5 * * * *'
        #   }
        # }
        #
        def load_from_hash(hash)
          array = hash.inject([]) do |out, (key, job)|
            job['name'] = key
            out << job
          end
          load_from_array array
        end

        # like to {#load_from_hash}
        # If exists old jobs in redis but removed from args, destroy old jobs
        def load_from_hash!(hash)
          destroy_removed_jobs(hash.keys)
          load_from_hash(hash)
        end

        # load cron jobs from Array
        # input structure should look like:
        # [
        #   {
        #     'name'        => 'name_of_job',
        #     'class'       => 'MyClass',
        #     'cron'        => '1 * * * *',
        #     'args'        => '(OPTIONAL) [Array or Hash]',
        #     'description' => '(OPTIONAL) Description of job'
        #   },
        #   {
        #     'name'  => 'Cool Job for Second Class',
        #     'class' => 'SecondClass',
        #     'cron'  => '*/5 * * * *'
        #   }
        # ]
        #
        def load_from_array(array)
          errors = {}
          array.each do |job_data|
            job = Sidekiq::Crond::Job.new(job_data)
            errors[job.name] = job.errors unless job.save
          end
          errors
        end

        # like to {#load_from_array}
        # If exists old jobs in redis but removed from args, destroy old jobs
        def load_from_array!(array)
          job_names = array.map { |job| job['name'] }
          destroy_removed_jobs(job_names)
          load_from_array(array)
        end

        # get all cron jobs
        def all
          job_hashes = Sidekiq.redis do |conn|
            members = conn.smembers(Sidekiq::Crond::JobKeys.jobs_key)
            conn.pipelined do
              members.map { |key| conn.hgetall(key) }
            end
          end
          job_hashes.compact.reject(&:empty?).collect do |h|
            # no need to fetch missing args from redis since we just got this hash from there
            Sidekiq::Crond::Job.new(h.merge(fetch_missing_args: false))
          end
        end

        def count
          Sidekiq.redis do |conn|
            conn.scard(Sidekiq::Crond::JobKeys.jobs_key)
          end
        end

        def exists?(name)
          Sidekiq.redis do |conn|
            conn.exists(Sidekiq::Crond::JobKeys.redis_key(name))
          end
        end

        def find(name)
          redis_key = Sidekiq::Crond::JobKeys.redis_key(name)
          Sidekiq.redis do |conn|
            Sidekiq::Crond::Job.new(conn.hgetall(redis_key)) if conn.exists(redis_key)
          end
        end

        # create new instance of cron job
        def create(hash)
          Sidekiq::Crond::Job.new(hash).save
        end

        # destroy job by name
        def destroy(name)
          if (job = find(name))
            job.destroy
          else
            false
          end
        end

        # remove all job from cron
        def destroy_all!
          all.each(&:destroy)
          Sidekiq.logger.info 'Cron Jobs - deleted all jobs'
        end

        # remove "removed jobs" between current jobs and new jobs
        def destroy_removed_jobs(new_job_names)
          current_job_names = all.map(&:name)
          removed_job_names = current_job_names - new_job_names
          removed_job_names.each { |j| destroy(j) }
          removed_job_names
        end
      end
    end
  end
end
