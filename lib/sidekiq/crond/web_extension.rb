# frozen_string_literal: true

module Sidekiq
  module Crond
    # Web interface
    module WebExtension
      class << self
        def registered(app)
          app.settings.locales << File.join(File.expand_path(__dir__), 'locales')

          jobs_list(app)
          job_show(app)
          change_job(app)
        end

        def jobs_list(app)
          # index page of cron jobs
          app.get '/cron' do
            @cron_jobs = Sidekiq::Crond::Jobs.all
            render_view('cron')
          end
        end

        def job_show(app)
          # display job detail + jid history
          app.get '/cron/:name' do
            @job = Sidekiq::Crond::Jobs.find(route_params[:name])
            if @job.present?
              render_view('cron_show')
            else
              redirect "#{root_path}cron"
            end
          end
        end

        def change_job(app)
          # enque cron job
          app.post '/cron/:name/:method' do
            job_method = get_job_method(route_params[:method])
            jobs_apply_method(route_params[:name], job_method)
            redirect params['redirect'] || "#{root_path}cron"
          end
        end

        def get_job_method(method)
          case method
          when 'disable'
            :disable!
          when 'delete'
            :destroy
          when 'enque'
            :enque!
          else
            :enable!
          end
        end

        def jobs_apply_method(name, method)
          if name == '__all__'
            Sidekiq::Crond::Jobs.all.each(&method)
          elsif (job = Sidekiq::Crond::Jobs.find(name))
            job.public_send(method)
          end
        end

        def view_path
          @view_path ||= File.join(File.expand_path(__dir__), 'views')
        end

        def render_view(view)
          render(:erb, File.read(File.join(view_path, "#{view}.erb")))
        end
      end
    end
  end
end
