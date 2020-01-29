# Sidekiq-Crond

A scheduling add-on for [Sidekiq](http://sidekiq.org).

Runs a thread alongside Sidekiq workers to schedule jobs at specified times (using cron notation `* * * * *` parsed by [Fugit](https://github.com/floraison/fugit), more about [cron notation](https://crontab.guru/).

Checks for new jobs to schedule every 30 seconds and doesn't schedule the same job multiple times when more than one Sidekiq worker is running.

Scheduling jobs are added only when at least one Sidekiq process is running, but it is safe to use Sidekiq-Crond in environments where multiple Sidekiq processes or nodes are running.

If you want to know how scheduling work, check out [under the hood](#under-the-hood)

Works with ActiveJob (Rails 4.2+)

You don't need Sidekiq PRO, you can use this gem with plain __Sidekiq__.

## Requirements

- Redis 2.8 or greater is required. (Redis 3.0.3 or greater is recommended for large scale use)
- Sidekiq 5 or greater is required

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-crond'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install sidekiq-crond

## Usage

If you are not using Rails, you need to add `require 'sidekiq-crond'` somewhere after `require 'sidekiq'`.

_Job properties_:

```ruby
{
 'name'  => 'name_of_job', #must be uniq!
 'cron'  => '1 * * * *',  # execute at 1 minute of every hour, ex: 12:01, 13:01, 14:01, 15:01...etc(HH:MM)
 'class' => 'MyClass',
 #OPTIONAL
 'queue' => 'name of queue',
 'args'  => '[Array or Hash] of arguments which will be passed to perform method',
 'date_as_argument' => true, # add the time of execution as last argument of the perform method
 'active_job' => true,  # enqueue job through rails 4.2+ active job interface
 'queue_name_prefix' => 'prefix', # rails 4.2+ active job queue with prefix
 'queue_name_delimiter' => '.',  # rails 4.2+ active job queue with custom delimiter
 'description' => 'A sentence describing what work this job performs.'  # Optional
}
```

### Time, cron and sidekiq-crond

For testing your cron notation you can use [crontab.guru](https://crontab.guru).

sidekiq-crond uses [Fugit](https://github.com/floraison/fugit) to parse the cronline.
If using Rails, this is evaluated against the timezone configured in Rails, otherwise the default is UTC.

If you want to have your jobs enqueued based on a different time zone you can specify a timezone in the cronline,
like this `'0 22 * * 1-5 America/Chicago'`.

See [rufus-scheduler documentation](https://github.com/jmettraux/rufus-scheduler#a-note-about-timezones) for more information. (note. Rufus scheduler is using Fugit under the hood, so documentation for Rufus Scheduler can help you also)

### What objects/classes can be scheduled
#### Sidekiq Worker
In this example, we are using `HardWorker` which looks like:
```ruby
class HardWorker
  include Sidekiq::Worker
  def perform(*args)
    # do something
  end
end
```

#### Active Job Worker
You can schedule: `ExampleJob` which looks like:
```ruby
class ExampleJob < ActiveJob::Base
  queue_as :default

  def perform(*args)
    # Do something
  end
end
```

#### Adding Cron job:
```ruby

class HardWorker
  include Sidekiq::Worker
  def perform(name, count)
    # do something
  end
end

Sidekiq::Cron::Job.create(name: 'Hard worker - every 5min', cron: '*/5 * * * *', class: 'HardWorker') # execute at every 5 minutes, ex: 12:05, 12:10, 12:15...etc
# => true
```

`create` method will return only true/false if job was saved or not.

```ruby
job = Sidekiq::Cron::Job.new(name: 'Hard worker - every 5min', cron: '*/5 * * * *', class: 'HardWorker')

if job.valid?
  job.save
else
  puts job.errors
end

#or simple

unless job.save
  puts job.errors #will return array of errors
end
```

Load more jobs from hash:
```ruby

hash = {
  'name_of_job' => {
    'class' => 'MyClass',
    'cron'  => '1 * * * *',
    'args'  => '(OPTIONAL) [Array or Hash]'
  },
  'My super iber cool job' => {
    'class' => 'SecondClass',
    'cron'  => '*/5 * * * *'
  }
}

Sidekiq::Cron::Job.load_from_hash hash
```

Load more jobs from array:
```ruby
array = [
  {
    'name'  => 'name_of_job',
    'class' => 'MyClass',
    'cron'  => '1 * * * *',
    'args'  => '(OPTIONAL) [Array or Hash]'
  },
  {
    'name'  => 'Cool Job for Second Class',
    'class' => 'SecondClass',
    'cron'  => '*/5 * * * *'
  }
]

Sidekiq::Crond::Job.load_from_array array
```

Bang-suffixed methods will remove jobs that are not present in the given hash/array,
update jobs that have the same names, and create new ones when the names are previously unknown.

```ruby
Sidekiq::Crond::Job#load_from_hash! hash
Sidekiq::Crond::Job#load_from_array! array
```

or from YML (same notation as Resque-scheduler)

```yaml
#config/schedule.yml

my_first_job:
  cron: "*/5 * * * *"
  class: "HardWorker"
  queue: hard_worker

second_job:
  cron: "*/30 * * * *" # execute at every 30 minutes
  class: "HardWorker"
  queue: hard_worker_long
  args:
    hard: "stuff"
```

```ruby
#initializers/sidekiq.rb
schedule_file = "config/schedule.yml"

if File.exist?(schedule_file) && Sidekiq.server?
  Sidekiq::Crond::Job.load_from_hash YAML.load_file(schedule_file)
end
```

or you can use for loading jobs from yml file [sidekiq-cron-tasks](https://github.com/coverhound/sidekiq-cron-tasks) which will add rake task `bundle exec rake sidekiq_cron:load` to your rails application.

#### Finding jobs
```ruby
#return array of all jobs
Sidekiq::Crond::Job.all

#return one job by its unique name - case sensitive
Sidekiq::Crond::Job.find "Job Name"

#return one job by its unique name - you can use hash with 'name' key
Sidekiq::Crond::Job.find name: "Job Name"

#if job can't be found nil is returned
```

#### Destroy jobs:
```ruby
#destroys all jobs
Sidekiq::Crond::Job.destroy_all!

#destroy job by its name
Sidekiq::Crond::Job.destroy "Job Name"

#destroy found job
Sidekiq::Crond::Job.find('Job name').destroy
```

#### Work with job:
```ruby
job = Sidekiq::Crond::Job.find('Job name')

#disable cron scheduling
job.disable!

#enable cron scheduling
job.enable!

#get status of job:
job.status
# => enabled/disabled

#enqueue job right now!
job.enque!
```

How to start scheduling?
Just start Sidekiq workers by running:

    sidekiq

### Web UI for Cron Jobs

If you are using Sidekiq's web UI and you would like to add cron jobs too to this web UI,
add `require 'sidekiq/crond/web'` after `require 'sidekiq/web'`.

### Forking Processes

If you're using a forking web server like Unicorn you may run into an issue where the Redis connection is used
before the process forks, causing the following exception

    Redis::InheritedError: Tried to use a connection from a child process without reconnecting. You need to reconnect to Redis after forking.

to occur. To avoid this, wrap your job creation in the call to `Sidekiq.configure_server`:

```ruby
Sidekiq.configure_server do |config|
  schedule_file = "config/schedule.yml"

  if File.exist?(schedule_file)
    Sidekiq::Crond::Job.load_from_hash YAML.load_file(schedule_file)
  end
end
```

## Under the hood

When you start the Sidekiq process, it starts one thread with `Sidekiq::Poller` instance, which perform the adding of scheduled jobs to queues, retries etc.

sidekiq-crond adds itself into this start procedure and starts another thread with `Sidekiq::Crond::Poller` which checks all enabled Sidekiq cron jobs every 10 seconds, if they should be added to queue (their cronline matches time of check).

sidekiq-crond is checking jobs to be enqueued every 30s by default, you can change it by setting:

```ruby
Sidekiq.options[:poll_interval] = 10
```

sidekiq-crond is safe to use with multiple sidekiq processes or nodes. It uses a Redis sorted set to determine that only the first process who asks can enqueue scheduled jobs into the queue.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/le0pard/sidekiq-crond. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/le0pard/sidekiq-crond/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Sidekiq::Crond project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/le0pard/sidekiq-crond/blob/master/CODE_OF_CONDUCT.md).
