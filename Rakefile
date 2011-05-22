require 'sinatra/activerecord'
require 'sinatra/activerecord/rake'

require 'heroku_backup_task'

task :cron do
  HerokuBackupTask.execute
end
