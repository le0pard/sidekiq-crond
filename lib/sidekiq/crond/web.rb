# frozen_string_literal: true

require 'sidekiq/crond/web_extension'
require 'sidekiq/crond/jobs'

if defined?(Sidekiq::Web)
  Sidekiq::Web.register Sidekiq::Crond::WebExtension
  Sidekiq::Web.tabs['Cron'] = 'cron'
end
