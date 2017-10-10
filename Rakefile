require 'bundler/setup'
require 'cfndsl/rake_task'


def rake_task(path, project, config = nil)
  name   = [project, config].compact.join('-')
  stack  = "stacks/#{name}.json"
  extras = [[:yaml, "config.yml"]]
  extras.push([:yaml, "configs/#{project}/#{config}.yml"]) if config

  CfnDsl::RakeTask.new(config) do |t|
    t.cfndsl_opts = {
      pretty: true,
      files: [{
        filename: path,
        output: stack
      }],
      extras: extras
    }
  end
end

namespace :generate do
  Dir['projects/*.rb'].each do |project_path|
    project = Pathname(project_path).basename.to_s.split('.').first.to_sym

    tasks = []

    namespace project do
      Dir["configs/#{project}/*.yml"].each do |config_path|
        config = Pathname(config_path).basename.to_s.split('.').first.to_sym
        tasks.push("#{project}:#{config}")

        rake_task(project_path, project, config)
      end
    end

    desc 'Generate Cloudformation'
    task project => tasks do
      if tasks.length == 0
        rake_task(project_path, project)
      end
    end
  end
end
